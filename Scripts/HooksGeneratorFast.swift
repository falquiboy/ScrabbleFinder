#!/usr/bin/env swift

import Foundation
import SQLite3

class FastHooksGenerator {
    private var db: OpaquePointer?
    private let spanishAlphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")
    
    init(dbPath: String) throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw NSError(domain: "HooksGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        
        // Create hooks table if it doesn't exist
        createHooksTable()
        optimizeDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func createHooksTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS word_hooks (
            word TEXT PRIMARY KEY,
            left_hooks TEXT,
            right_hooks TEXT
        );
        """
        
        sqlite3_exec(db, sql, nil, nil, nil)
        
        // Create index for faster lookups
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_word_hooks ON word_hooks(word);", nil, nil, nil)
    }
    
    private func optimizeDatabase() {
        // SQLite optimizations for batch operations
        sqlite3_exec(db, "PRAGMA synchronous = OFF;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode = MEMORY;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size = 100000;", nil, nil, nil)
    }
    
    func generateHooksFast() {
        print("🚀 Starting FAST hooks generation...")
        
        // 1. Get all words and create a Set for O(1) lookup
        let words = getAllWords()
        let wordSet = Set(words)
        print("📚 Loaded \(words.count) words into memory")
        
        // 2. Process in batches with transactions for speed
        let batchSize = 5000
        var processed = 0
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        for i in stride(from: 0, to: words.count, by: batchSize) {
            let endIndex = min(i + batchSize, words.count)
            let batch = Array(words[i..<endIndex])
            
            for word in batch {
                let hooks = generateHooksForWord(word, wordSet: wordSet)
                saveHooksOptimized(hooks)
                processed += 1
            }
            
            // Commit batch and start new transaction
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            
            let percentage = (Double(processed) / Double(words.count)) * 100
            print("⚡ Progress: \(processed)/\(words.count) (\(String(format: "%.1f", percentage))%)")
        }
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        print("🎉 FAST generation completed! Processed \(processed) words")
    }
    
    private func getAllWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT DISTINCT word FROM words ORDER BY word"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    words.append(String(cString: cString))
                }
            }
        }
        
        sqlite3_finalize(stmt)
        return words
    }
    
    private func generateHooksForWord(_ word: String, wordSet: Set<String>) -> (word: String, left: String, right: String) {
        var leftHooks = ""
        var rightHooks = ""
        
        for letter in spanishAlphabet {
            // Test left hook
            if wordSet.contains(String(letter) + word) {
                leftHooks += String(letter)
            }
            
            // Test right hook
            if wordSet.contains(word + String(letter)) {
                rightHooks += String(letter)
            }
        }
        
        return (word, leftHooks, rightHooks)
    }
    
    private var insertStmt: OpaquePointer?
    
    private func saveHooksOptimized(_ hooks: (word: String, left: String, right: String)) {
        if insertStmt == nil {
            let sql = "INSERT OR REPLACE INTO word_hooks (word, left_hooks, right_hooks) VALUES (?, ?, ?)"
            sqlite3_prepare_v2(db, sql, -1, &insertStmt, nil)
        }
        
        sqlite3_bind_text(insertStmt, 1, hooks.word, -1, nil)
        sqlite3_bind_text(insertStmt, 2, hooks.left, -1, nil)
        sqlite3_bind_text(insertStmt, 3, hooks.right, -1, nil)
        sqlite3_step(insertStmt)
        sqlite3_reset(insertStmt)
    }
}

// MARK: - Main Execution
func main() {
    print("⚡ ScrabbleFinder FAST Hooks Generator")
    print("====================================")
    
    let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    do {
        let generator = try FastHooksGenerator(dbPath: dbPath)
        let startTime = Date()
        generator.generateHooksFast()
        let duration = Date().timeIntervalSince(startTime)
        print("⏱️  Total time: \(String(format: "%.1f", duration)) seconds")
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

main()