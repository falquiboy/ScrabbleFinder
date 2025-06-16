#!/usr/bin/env swift

import Foundation
import SQLite3

class PersistentHooksGenerator {
    private var db: OpaquePointer?
    private let spanishAlphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")
    private let dbPath: String
    
    init(dbPath: String) throws {
        self.dbPath = dbPath
        
        // Make backup first
        let backupPath = dbPath + ".backup"
        try? FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
        print("📋 Database backup created at: \(backupPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw NSError(domain: "HooksGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        
        setupDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func setupDatabase() {
        print("🔧 Setting up database for hooks generation...")
        
        // Drop existing hooks table to start fresh
        sqlite3_exec(db, "DROP TABLE IF EXISTS word_hooks;", nil, nil, nil)
        
        // Create hooks table
        let createTable = """
        CREATE TABLE word_hooks (
            word TEXT PRIMARY KEY,
            left_hooks TEXT NOT NULL DEFAULT '',
            right_hooks TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        if sqlite3_exec(db, createTable, nil, nil, nil) != SQLITE_OK {
            print("❌ Error creating table: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        // Create index for performance
        sqlite3_exec(db, "CREATE INDEX idx_word_hooks_word ON word_hooks(word);", nil, nil, nil)
        
        // Set pragmas for MAXIMUM persistence and performance
        sqlite3_exec(db, "PRAGMA synchronous = FULL;", nil, nil, nil)      // Ensure disk writes
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)      // Write-Ahead Logging
        sqlite3_exec(db, "PRAGMA cache_size = 50000;", nil, nil, nil)      // Large cache
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY;", nil, nil, nil)     // Temp in memory
        
        print("✅ Database setup complete with persistence mode")
    }
    
    func generateAllHooksPersistent() {
        print("🚀 Starting PERSISTENT hooks generation...")
        print("═══════════════════════════════════════════════")
        
        let startTime = Date()
        
        // Load all words
        print("📚 Loading all words into memory...")
        let words = getAllWords()
        let wordSet = Set(words)
        print("✅ Loaded \(words.count) words into memory")
        print("🔍 Dictionary contains \(wordSet.count) unique words for lookup")
        
        // Process in smaller batches for better progress reporting
        let batchSize = 1000
        var totalProcessed = 0
        var totalHooksFound = 0
        let totalWords = words.count
        
        // Prepare optimized insert statement
        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT INTO word_hooks (word, left_hooks, right_hooks) VALUES (?, ?, ?)"
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
            print("❌ Failed to prepare insert statement")
            return
        }
        
        print("\n🔄 Starting batch processing...")
        print("Progress format: [Batch] Words processed | Hooks found | Percentage | ETA")
        print("─────────────────────────────────────────────────────────────────────────")
        
        for batchStart in stride(from: 0, to: totalWords, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalWords)
            let batch = Array(words[batchStart..<batchEnd])
            let batchNumber = (batchStart / batchSize) + 1
            let totalBatches = (totalWords + batchSize - 1) / batchSize
            
            // Begin transaction for this batch
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
            
            var batchHooksFound = 0
            
            for word in batch {
                let hooks = generateHooksForWord(word, wordSet: wordSet)
                
                // Insert into database
                sqlite3_bind_text(insertStmt, 1, hooks.word, -1, nil)
                sqlite3_bind_text(insertStmt, 2, hooks.left, -1, nil)
                sqlite3_bind_text(insertStmt, 3, hooks.right, -1, nil)
                
                if sqlite3_step(insertStmt) != SQLITE_DONE {
                    print("❌ Error inserting \(word): \(String(cString: sqlite3_errmsg(db)))")
                }
                sqlite3_reset(insertStmt)
                
                if !hooks.left.isEmpty || !hooks.right.isEmpty {
                    batchHooksFound += 1
                }
                
                totalProcessed += 1
            }
            
            // Commit transaction and force sync
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA wal_checkpoint;", nil, nil, nil)  // Force WAL sync
            
            totalHooksFound += batchHooksFound
            
            // Calculate progress and ETA
            let percentage = Double(totalProcessed) / Double(totalWords) * 100
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(totalProcessed) / elapsed
            let remaining = Double(totalWords - totalProcessed) / rate
            let eta = formatTime(remaining)
            
            // Progress line
            print("[\(String(format: "%3d", batchNumber))/\(totalBatches)] \(String(format: "%6d", totalProcessed)) words | \(String(format: "%5d", totalHooksFound)) hooks | \(String(format: "%5.1f", percentage))% | ETA: \(eta)")
            
            // Verification every 10 batches
            if batchNumber % 10 == 0 {
                let dbCount = getHooksCount()
                if dbCount != totalProcessed {
                    print("⚠️  Database verification: Expected \(totalProcessed), found \(dbCount)")
                } else {
                    print("✅ Database verification: \(dbCount) records confirmed")
                }
            }
        }
        
        sqlite3_finalize(insertStmt)
        
        // Final verification and statistics
        let finalCount = getHooksCount()
        let duration = Date().timeIntervalSince(startTime)
        
        print("─────────────────────────────────────────────────────────────────────────")
        print("🎉 GENERATION COMPLETED!")
        print("📊 FINAL STATISTICS:")
        print("   • Words processed: \(totalProcessed)")
        print("   • Words with hooks: \(totalHooksFound)")
        print("   • Database records: \(finalCount)")
        print("   • Success rate: \(String(format: "%.1f", Double(totalHooksFound)/Double(totalProcessed)*100))%")
        print("   • Total time: \(formatTime(duration))")
        print("   • Average rate: \(String(format: "%.0f", Double(totalProcessed)/duration)) words/sec")
        print("📁 Database path: \(dbPath)")
        
        // Sample results
        print("\n🔍 SAMPLE RESULTS:")
        showSampleHooks()
        
        if finalCount == totalProcessed {
            print("✅ All records successfully persisted to database!")
        } else {
            print("⚠️  Warning: Record count mismatch!")
        }
    }
    
    private func getAllWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT DISTINCT word FROM words ORDER BY LENGTH(word), word"
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
    
    private func getHooksCount() -> Int {
        let sql = "SELECT COUNT(*) FROM word_hooks"
        var stmt: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        
        sqlite3_finalize(stmt)
        return count
    }
    
    private func showSampleHooks() {
        let sql = """
        SELECT word, left_hooks, right_hooks 
        FROM word_hooks 
        WHERE length(left_hooks) > 0 OR length(right_hooks) > 0 
        ORDER BY length(left_hooks) + length(right_hooks) DESC 
        LIMIT 10
        """
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = String(cString: sqlite3_column_text(stmt, 0))
                let left = String(cString: sqlite3_column_text(stmt, 1))
                let right = String(cString: sqlite3_column_text(stmt, 2))
                
                let display = left.lowercased() + word + right.lowercased()
                print("   \(display)")
            }
        }
        
        sqlite3_finalize(stmt)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m\(remainingSeconds)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h\(minutes)m"
        }
    }
}

// MARK: - Main Execution
func main() {
    print("⚡ ScrabbleFinder PERSISTENT Hooks Generator")
    print("==========================================")
    
    let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    do {
        let generator = try PersistentHooksGenerator(dbPath: dbPath)
        generator.generateAllHooksPersistent()
        
        print("\n✅ Process completed successfully!")
        print("🔗 Hooks are now available in your ScrabbleFinder app")
        
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

main()