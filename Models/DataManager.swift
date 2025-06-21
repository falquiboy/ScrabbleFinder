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
    @Published var isDataReady = false  // True when either trie OR SQLite is ready
    private var trieRoot: TrieNode?
    private var sqliteDB: OpaquePointer?
    private var hooksDB: OpaquePointer?
    
    // MARK: - Caches
    private var hooksCache: [String: WordHooks] = [:]
    private var anagramCache: [String: [String]] = [:]
    private let maxCacheSize = 10000
    private let maxAnagramCacheSize = 1000
    
    // MARK: - Initialization
    
    init() {
        setupDatabase()
        setupHooksDatabase()
        
        // Mark data as ready immediately if SQLite is available (fallback ready)
        DispatchQueue.main.async {
            self.isDataReady = (self.sqliteDB != nil)
            if self.isDataReady {
                print("✅ SQLite fallback ready - searches can begin")
            }
        }
        
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
                        self.isDataReady = true  // Ensure data is ready with trie
                        print("✅ Trie loaded successfully - optimal performance ready")
                    }
                } catch {
                    print("❌ Error decoding trie: \(error)")
                    DispatchQueue.main.async {
                        self.isTrieReady = false
                        // Keep isDataReady true if SQLite is available as fallback
                        print("⚠️ Trie failed but SQLite fallback still available")
                    }
                }
            } else {
                print("❌ Could not load trie.bin from bundle")
                DispatchQueue.main.async {
                    // Keep isDataReady true if SQLite is available as fallback
                    print("⚠️ Trie load failed but SQLite fallback still available")
                }
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
            print("❌ SQLite database file not found")
            return
        }
        
        if sqlite3_open_v2(dbPath, &sqliteDB, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("❌ Error opening SQLite database")
            sqliteDB = nil
        } else {
            print("✅ SQLite database connected successfully")
            
            // Verify table structure and data
            let tableCheckQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='words';"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(sqliteDB, tableCheckQuery, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    print("✅ words table exists")
                    
                    // Check row count for confidence
                    let countQuery = "SELECT COUNT(*) FROM words;"
                    var countStatement: OpaquePointer?
                    
                    if sqlite3_prepare_v2(sqliteDB, countQuery, -1, &countStatement, nil) == SQLITE_OK {
                        if sqlite3_step(countStatement) == SQLITE_ROW {
                            let count = sqlite3_column_int(countStatement, 0)
                            print("📊 SQLite database ready with \(count) words")
                        }
                    }
                    sqlite3_finalize(countStatement)
                } else {
                    print("❌ words table does NOT exist in SQLite")
                }
            }
            sqlite3_finalize(statement)
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
    
    // MARK: - System Status
    
    /// Indicates if any data source is ready for queries
    var canPerformQueries: Bool {
        return isDataReady
    }
    
    /// Indicates current data source being used
    var currentDataSource: String {
        if isTrieReady {
            return "Trie (Optimal)"
        } else if sqliteDB != nil {
            return "SQLite (Fallback)"
        } else {
            return "None (No Data)"
        }
    }
    
    /// Performance level based on data source
    var performanceLevel: String {
        if isTrieReady {
            return "High"
        } else if sqliteDB != nil {
            return "Medium"
        } else {
            return "None"
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
        print("🔄 Using SQLite fallback for word validation: \(word)")
        return validateWordInDatabase(normalizedWord)
    }
    
    /// Finds anagrams using alphagram lookup
    func findAnagrams(for letters: String) -> [String] {
        let normalizedLetters = SpanishUtils.normalize(letters)
        let alphagram = SpanishUtils.generateAlphagram(normalizedLetters)
        print("🔍 DataManager: letters='\(letters)' -> normalized='\(normalizedLetters)' -> alphagram='\(alphagram)'")
        return findAnagramsByAlphagram(alphagram)
    }
    
    /// Search result with timing information
    struct SearchResult {
        let words: [String]
        let executionTime: TimeInterval
        let source: String
        let isCacheHit: Bool
    }
    
    /// Finds anagrams by precomputed alphagram with caching and timing
    func findAnagramsByAlphagram(_ alphagram: String) -> [String] {
        let searchResult = findAnagramsWithTiming(alphagram)
        return searchResult.words
    }
    
    /// Finds anagrams with detailed performance information
    func findAnagramsWithTiming(_ alphagram: String) -> SearchResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check cache first for blazing fast repeated searches
        if let cached = anagramCache[alphagram] {
            let executionTime = CFAbsoluteTimeGetCurrent() - startTime
            print("⚡ Cache HIT for alphagram: \(alphagram) (\(cached.count) results)")
            return SearchResult(
                words: cached, 
                executionTime: executionTime, 
                source: "Cache", 
                isCacheHit: true
            )
        }
        
        let results: [String]
        let source: String
        
        // Try trie first if available
        if isTrieReady, let trie = trieRoot {
            let trieResults = trie.searchByAlphagram(alphagram)
            results = trieResults.map { SpanishUtils.denormalize($0) }
                               .sorted(by: SpanishUtils.compareSpanishOrder)
            source = "Trie"
        } else {
            // Fallback to SQLite
            print("🔄 Using SQLite fallback for anagram search: \(alphagram)")
            results = findAnagramsInDatabase(alphagram)
            source = "SQLite"
        }
        
        // Cache results with size management
        cacheAnagramResults(alphagram: alphagram, results: results)
        
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return SearchResult(
            words: results, 
            executionTime: executionTime, 
            source: source, 
            isCacheHit: false
        )
    }
    
    /// SQLite search with optional length constraint for performance
    private func findAnagramsInDatabase(_ alphagram: String, length: Int? = nil) -> [String] {
        guard let db = sqliteDB else { 
            print("❌ No SQLite database available")
            return [] 
        }
        
        // Build optimized query with length filter if specified
        let baseQuery = "SELECT word FROM words WHERE alphagram = ?"
        let query = if let targetLength = length {
            baseQuery + " AND LENGTH(word) = ? ORDER BY word"
        } else {
            baseQuery + " ORDER BY word"
        }
        
        print("🔍 SQLite: Optimized search - alphagram: '\(alphagram)' length: \(length?.description ?? "any")")
        
        var statement: OpaquePointer?
        var results: [String] = []
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ SQLite: Failed to prepare optimized query")
            return []
        }
        
        // Bind parameters
        sqlite3_bind_text(statement, 1, alphagram, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let targetLength = length {
            sqlite3_bind_int(statement, 2, Int32(targetLength))
        }
        
        var rowCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        while sqlite3_step(statement) == SQLITE_ROW {
            rowCount += 1
            if let wordPtr = sqlite3_column_text(statement, 0) {
                let word = String(cString: wordPtr)
                let denormalized = SpanishUtils.denormalize(word)
                results.append(denormalized)
            }
        }
        
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        print("🚀 SQLite: Found \(rowCount) results in \(String(format: "%.3f", executionTime))s")
        
        return results.sorted(by: SpanishUtils.compareSpanishOrder)
    }
    
    /// Finds anagrams by alphagram with length constraint for blazing fast searches
    func findAnagramsByAlphagram(_ alphagram: String, length: Int?) -> [String] {
        // Try trie first if available
        if isTrieReady, let trie = trieRoot {
            let results = trie.searchByAlphagram(alphagram)
            let denormalized = results.map { SpanishUtils.denormalize($0) }
            
            // Apply length filter if specified
            if let targetLength = length {
                return denormalized.filter { $0.count == targetLength }
                                 .sorted(by: SpanishUtils.compareSpanishOrder)
            } else {
                return denormalized.sorted(by: SpanishUtils.compareSpanishOrder)
            }
        }
        
        // Fallback to SQLite with length optimization
        print("🔄 Using SQLite fallback for anagram search: \(alphagram) (length: \(length?.description ?? "any"))")
        return findAnagramsInDatabase(alphagram, length: length)
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
    
    /// Cache anagram results with size management
    private func cacheAnagramResults(alphagram: String, results: [String]) {
        // Manage cache size
        if anagramCache.count >= maxAnagramCacheSize {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(anagramCache.keys.prefix(maxAnagramCacheSize / 4))
            keysToRemove.forEach { anagramCache.removeValue(forKey: $0) }
            print("🧹 Cleaned anagram cache - removed \(keysToRemove.count) entries")
        }
        
        anagramCache[alphagram] = results
        print("💾 Cached anagram results for '\(alphagram)' (\(results.count) words)")
    }
    
    /// Clear anagram cache to free memory
    func clearAnagramCache() {
        anagramCache.removeAll()
        print("🧹 Anagram cache cleared")
    }
    
    /// Clear all caches
    func clearAllCaches() {
        clearHooksCache()
        clearAnagramCache()
        print("🧹 All caches cleared")
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
    
    /// Gets all words from the data source for pattern search
    func getAllWords() -> [String] {
        // Try trie first if available (more efficient)
        if isTrieReady, let trie = trieRoot {
            return trie.allWords().map { SpanishUtils.denormalize($0) }
        }
        
        // Fallback to SQLite
        print("🔄 Using SQLite fallback for pattern search - may be slower on physical devices")
        return getAllWordsFromDatabase()
    }
    
    // MARK: - Private SQLite Queries
    
    private func getAllWordsFromDatabase() -> [String] {
        guard let db = sqliteDB else { return [] }
        
        let query = "SELECT word FROM words ORDER BY word"
        var statement: OpaquePointer?
        var results: [String] = []
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare getAllWords query")
            return []
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let wordPtr = sqlite3_column_text(statement, 0) {
                let word = String(cString: wordPtr)
                let denormalized = SpanishUtils.denormalize(word)
                results.append(denormalized)
            }
        }
        
        print("📚 Loaded \(results.count) words from SQLite")
        return results
    }
    
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
    
    
}