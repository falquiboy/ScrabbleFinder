import Foundation
import TrieKit
import SQLite3

// MARK: - Data Manager
// Handles trie and SQLite data sources

// MARK: - Hooks Data Structure
struct WordHooks {
    let word: String
    let leftExternal: String
    let rightExternal: String
    let leftInternal: String
    let rightInternal: String
    
    var hasExternalHooks: Bool {
        return !leftExternal.isEmpty || !rightExternal.isEmpty
    }
    
    var hasInternalHooks: Bool {
        return !leftInternal.isEmpty || !rightInternal.isEmpty
    }
    
    var hasAnyHooks: Bool {
        return hasExternalHooks || hasInternalHooks
    }
    
    /// Formatted display with external hooks: "abCASAde"
    var externalDisplay: String {
        return leftExternal.lowercased() + word + rightExternal.lowercased()
    }
    
    /// Formatted display with internal hooks: "[C]ASA" or "CAS[A]" or "[C]AS[A]"
    var internalDisplay: String {
        var display = word
        if !leftInternal.isEmpty {
            display = "[\(leftInternal.lowercased())]" + String(display.dropFirst())
        }
        if !rightInternal.isEmpty {
            display = String(display.dropLast()) + "[\(rightInternal.lowercased())]"
        }
        return display
    }
}

class DataManager: ObservableObject {
    
    // MARK: - Data Sources
    @Published var isTrieReady = false
    private var trieRoot: TrieNode?
    private var sqliteDB: OpaquePointer?
    private var hooksDB: OpaquePointer?
    
    // MARK: - Hooks Cache
    private var hooksCache: [String: WordHooks] = [:]
    private let maxCacheSize = 10000
    
    // MARK: - Initialization
    
    init() {
        setupDatabase()
        setupHooksDatabase()
        loadTrie()
    }
    
    deinit {
        closeDatabaseConnection()
        closeHooksConnection()
    }
    
    // MARK: - Trie Management
    
    private func loadTrie() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let trieData = self.loadTrieFromBundle() {
                do {
                    let decoder = PropertyListDecoder()
                    let trie = try decoder.decode(TrieNode.self, from: trieData)
                    
                    DispatchQueue.main.async {
                        self.trieRoot = trie
                        self.isTrieReady = true
                        print("✅ Trie loaded successfully")
                    }
                } catch {
                    print("❌ Error decoding trie: \(error)")
                    DispatchQueue.main.async {
                        self.isTrieReady = false
                    }
                }
            } else {
                print("❌ Could not load trie.bin from bundle")
            }
        }
    }
    
    private func loadTrieFromBundle() -> Data? {
        guard let url = Bundle.main.url(forResource: "trie", withExtension: "bin") else {
            print("trie.bin not found in bundle")
            return nil
        }
        
        do {
            return try Data(contentsOf: url)
        } catch {
            print("Error loading trie.bin: \(error)")
            return nil
        }
    }
    
    // MARK: - SQLite Management
    
    private func setupDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "scrabble_words", ofType: "sqlite") else {
            print("Database file not found")
            return
        }
        
        if sqlite3_open_v2(dbPath, &sqliteDB, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Error opening database")
            sqliteDB = nil
        }
    }
    
    private func setupHooksDatabase() {
        guard let hooksPath = Bundle.main.path(forResource: "scrabble_hooks", ofType: "sqlite") else {
            print("⚠️ Hooks database not found - hooks features will be disabled")
            return
        }
        
        print("🔍 Hooks database path: \(hooksPath)")
        
        if sqlite3_open_v2(hooksPath, &hooksDB, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("❌ Error opening hooks database")
            hooksDB = nil
        } else {
            print("✅ Hooks database connected successfully")
            
            // Verify table exists and has data
            let tableCheckQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='word_hooks';"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(hooksDB, tableCheckQuery, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    print("✅ word_hooks table exists")
                    
                    // Check row count
                    let countQuery = "SELECT COUNT(*) FROM word_hooks;"
                    var countStatement: OpaquePointer?
                    
                    if sqlite3_prepare_v2(hooksDB, countQuery, -1, &countStatement, nil) == SQLITE_OK {
                        if sqlite3_step(countStatement) == SQLITE_ROW {
                            let count = sqlite3_column_int(countStatement, 0)
                            print("📊 word_hooks table has \(count) rows")
                        }
                    }
                    sqlite3_finalize(countStatement)
                } else {
                    print("❌ word_hooks table does NOT exist")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    private func closeDatabaseConnection() {
        if let db = sqliteDB {
            sqlite3_close(db)
            sqliteDB = nil
        }
    }
    
    private func closeHooksConnection() {
        if let db = hooksDB {
            sqlite3_close(db)
            hooksDB = nil
        }
    }
    
    // MARK: - Query Methods
    
    /// Validates a single word using trie (preferred) or SQLite fallback
    func validateWord(_ word: String) -> Bool {
        let normalizedWord = SpanishUtils.normalize(word)
        
        // Try trie first if available
        if isTrieReady, let trie = trieRoot {
            // Check if word exists by searching for its alphagram and checking if normalized word is in results
            let alphagram = SpanishUtils.generateAlphagram(normalizedWord)
            let anagrams = trie.searchByAlphagram(alphagram)
            return anagrams.contains(normalizedWord)
        }
        
        // Fallback to SQLite
        return validateWordInDatabase(normalizedWord)
    }
    
    /// Finds anagrams using alphagram lookup
    func findAnagrams(for letters: String) -> [String] {
        let normalizedLetters = SpanishUtils.normalize(letters)
        let alphagram = SpanishUtils.generateAlphagram(normalizedLetters)
        return findAnagramsByAlphagram(alphagram)
    }
    
    /// Finds anagrams by precomputed alphagram
    func findAnagramsByAlphagram(_ alphagram: String) -> [String] {
        // Try trie first if available
        if isTrieReady, let trie = trieRoot {
            let results = trie.searchByAlphagram(alphagram)
            return results.map { SpanishUtils.denormalize($0) }
                         .sorted(by: SpanishUtils.compareSpanishOrder)
        }
        
        // Fallback to SQLite
        return findAnagramsInDatabase(alphagram)
    }
    
    // MARK: - Hooks Methods
    
    /// Get hooks for a single word with intelligent caching
    func getHooks(for word: String) -> WordHooks? {
        let normalizedWord = word.uppercased()
        print("🔍 Getting hooks for: \(word) -> \(normalizedWord)")
        
        // Check cache first
        if let cached = hooksCache[normalizedWord] {
            print("💾 Found hooks in cache for \(normalizedWord)")
            return cached
        }
        
        // Load from hooks database
        guard let hooks = loadHooksFromDatabase(normalizedWord) else {
            return nil
        }
        
        // Cache with size management
        if hooksCache.count >= maxCacheSize {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(hooksCache.keys.prefix(maxCacheSize / 4))
            keysToRemove.forEach { hooksCache.removeValue(forKey: $0) }
        }
        
        hooksCache[normalizedWord] = hooks
        return hooks
    }
    
    /// Batch load hooks for multiple words efficiently
    func getHooks(for words: [String]) -> [String: WordHooks] {
        print("🔍 Batch getHooks called with: \(words)")
        var result: [String: WordHooks] = [:]
        var wordsToLoad: [String] = []
        
        // Check cache first
        for word in words {
            let normalizedWord = word.uppercased()
            if let cached = hooksCache[normalizedWord] {
                result[word] = cached
                print("💾 Found \(word) in cache")
            } else {
                wordsToLoad.append(normalizedWord)
                print("🔄 Need to load \(word) -> \(normalizedWord)")
            }
        }
        
        // Batch load missing words
        if !wordsToLoad.isEmpty {
            print("🔍 Loading \(wordsToLoad.count) words from database")
            
            // Try individual loading as a fallback to test if batch is the issue
            print("🔍 Testing individual loading...")
            for word in wordsToLoad {
                if let hooks = loadHooksFromDatabase(word) {
                    print("✅ Individual load worked for \(word)")
                    result[words.first { $0.uppercased() == word } ?? word] = hooks
                    hooksCache[word] = hooks
                } else {
                    print("❌ Individual load failed for \(word)")
                }
            }
            
            let batchHooks = loadHooksBatch(wordsToLoad)
            print("🔍 Got \(batchHooks.count) hooks from batch loading")
            
            // Map normalized words back to original words (only if individual didn't work)
            if result.isEmpty {
                for word in words {
                    let normalizedWord = word.uppercased()
                    if let hooks = batchHooks[normalizedWord] {
                        result[word] = hooks
                        hooksCache[normalizedWord] = hooks
                        print("✅ Mapped \(normalizedWord) -> \(word)")
                    }
                }
            }
        }
        
        print("🔍 Final batch result: \(result.count) hooks for \(words.count) words")
        return result
    }
    
    /// Clear hooks cache to free memory
    func clearHooksCache() {
        hooksCache.removeAll()
    }
    
    // MARK: - Private Hooks Database Queries
    
    private func loadHooksFromDatabase(_ word: String) -> WordHooks? {
        guard let db = hooksDB else { 
            print("🔍 No hooks database available")
            return nil 
        }
        
        let query = """
            SELECT left_external, right_external, left_internal, right_internal 
            FROM word_hooks 
            WHERE word = ? LIMIT 1
        """
        
        var statement: OpaquePointer?
        var hooks: WordHooks?
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare hooks query for word: \(word)")
            return nil
        }
        
        // Bind word parameter using SQLITE_TRANSIENT so SQLite makes its own copy
        sqlite3_bind_text(statement, 1, word, -1,
                         unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let leftExternal = String(cString: sqlite3_column_text(statement, 0))
            let rightExternal = String(cString: sqlite3_column_text(statement, 1))
            let leftInternal = String(cString: sqlite3_column_text(statement, 2))
            let rightInternal = String(cString: sqlite3_column_text(statement, 3))
            
            hooks = WordHooks(
                word: word,
                leftExternal: leftExternal,
                rightExternal: rightExternal,
                leftInternal: leftInternal,
                rightInternal: rightInternal
            )
            
            print("🎯 Found hooks for \(word): ext(\(leftExternal),\(rightExternal)) int(\(leftInternal),\(rightInternal))")
        } else {
            print("📭 No hooks found for word: \(word)")
        }
        
        return hooks
    }
    
    private func loadHooksBatch(_ words: [String]) -> [String: WordHooks] {
        guard let db = hooksDB, !words.isEmpty else { 
            print("🔍 No hooks database or empty words list")
            return [:]
        }
        
        print("🔍 Loading hooks batch for \(words.count) words: \(words)")
        var result: [String: WordHooks] = [:]
        
        // Create placeholder string for IN clause
        let placeholders = Array(repeating: "?", count: words.count).joined(separator: ",")
        let query = """
            SELECT word, left_external, right_external, left_internal, right_internal 
            FROM word_hooks 
            WHERE word IN (\(placeholders))
        """
        
        print("🔍 Batch query: \(query)")
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare batch hooks query")
            return [:]
        }
        
        // Bind parameters
        for (index, word) in words.enumerated() {
            // Bind each word parameter so SQLite copies the text (SQLITE_TRANSIENT)
            sqlite3_bind_text(statement,
                             Int32(index + 1),
                             word,
                             -1,
                             unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            print("🔗 Binding parameter \(index + 1): '\(word)'")
        }
        
        print("🔍 Executing query...")
        
        // Process results
        var rowCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            rowCount += 1
            let word = String(cString: sqlite3_column_text(statement, 0))
            let leftExternal = String(cString: sqlite3_column_text(statement, 1))
            let rightExternal = String(cString: sqlite3_column_text(statement, 2))
            let leftInternal = String(cString: sqlite3_column_text(statement, 3))
            let rightInternal = String(cString: sqlite3_column_text(statement, 4))
            
            print("🎯 Found batch hooks for \(word): ext(\(leftExternal),\(rightExternal)) int(\(leftInternal),\(rightInternal))")
            
            let hooks = WordHooks(
                word: word,
                leftExternal: leftExternal,
                rightExternal: rightExternal,
                leftInternal: leftInternal,
                rightInternal: rightInternal
            )
            
            result[word] = hooks
        }
        
        print("🔍 Query executed, found \(rowCount) rows")
        print("🔍 Batch loading returned \(result.count) hooks")
        return result
    }
    
    // MARK: - Private SQLite Queries
    
    private func validateWordInDatabase(_ word: String) -> Bool {
        guard let db = sqliteDB else { return false }
        
        let query = "SELECT 1 FROM words WHERE word = ? LIMIT 1"
        var statement: OpaquePointer?
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        sqlite3_bind_text(statement, 1, word, -1,
                         unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    private func findAnagramsInDatabase(_ alphagram: String) -> [String] {
        guard let db = sqliteDB else { return [] }
        
        let query = "SELECT word FROM words WHERE alphagram = ? ORDER BY word"
        var statement: OpaquePointer?
        var results: [String] = []
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        sqlite3_bind_text(statement, 1, alphagram, -1, nil)
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let wordPtr = sqlite3_column_text(statement, 0) {
                let word = String(cString: wordPtr)
                let denormalized = SpanishUtils.denormalize(word)
                results.append(denormalized)
            }
        }
        
        return results.sorted(by: SpanishUtils.compareSpanishOrder)
    }
}