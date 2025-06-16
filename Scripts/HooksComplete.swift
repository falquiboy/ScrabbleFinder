#!/usr/bin/env swift

import Foundation
import SQLite3

class CompleteHooksGenerator {
    private var db: OpaquePointer?
    private let spanishAlphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")
    private let dbPath: String
    private let logFile: String
    
    init(dbPath: String) throws {
        self.dbPath = dbPath
        self.logFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_hooks_log.txt")
        
        // Create backup
        let backupPath = dbPath + ".pre_hooks_backup"
        try? FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
        self.log("📋 Backup created: \(backupPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw NSError(domain: "HooksGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        
        setupDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        print(message)
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let fileHandle = FileHandle(forWritingAtPath: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logFile))
            }
        }
    }
    
    private func setupDatabase() {
        log("🔧 Setting up database for complete hooks generation...")
        
        // Configure for maximum reliability
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size=50000;", nil, nil, nil)
        
        // Drop and recreate hooks table
        sqlite3_exec(db, "DROP TABLE IF EXISTS word_hooks;", nil, nil, nil)
        
        let createTable = """
        CREATE TABLE word_hooks (
            word TEXT PRIMARY KEY,
            left_hooks TEXT NOT NULL DEFAULT '',
            right_hooks TEXT NOT NULL DEFAULT '',
            left_internal_hooks TEXT NOT NULL DEFAULT '',
            right_internal_hooks TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        if sqlite3_exec(db, createTable, nil, nil, nil) != SQLITE_OK {
            log("❌ Error creating table: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        sqlite3_exec(db, "CREATE INDEX idx_word_hooks_word ON word_hooks(word);", nil, nil, nil)
        log("✅ Database setup complete")
    }
    
    func generateCompleteHooks() {
        log("🚀 Starting COMPLETE hooks generation...")
        log("═══════════════════════════════════════════")
        
        let startTime = Date()
        
        // Load all words
        log("📚 Loading dictionary...")
        let allWords = getAllWords()
        let wordSet = Set(allWords)
        log("✅ Loaded \(allWords.count) words")
        
        // Process in batches
        let batchSize = 2000
        var totalProcessed = 0
        var totalWithExternalHooks = 0
        var totalWithInternalHooks = 0
        
        // Prepare insert statement
        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT INTO word_hooks (word, left_hooks, right_hooks, left_internal_hooks, right_internal_hooks) VALUES (?, ?, ?, ?, ?)"
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
            log("❌ Failed to prepare insert statement")
            return
        }
        
        log("⚡ Processing \(allWords.count) words in batches of \(batchSize)...")
        log("Progress: [Batch] Processed | Ext.Hooks | Int.Hooks | Percentage | ETA")
        log("────────────────────────────────────────────────────────────────────")
        
        for batchStart in stride(from: 0, to: allWords.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allWords.count)
            let batch = Array(allWords[batchStart..<batchEnd])
            let batchNumber = (batchStart / batchSize) + 1
            let totalBatches = (allWords.count + batchSize - 1) / batchSize
            
            // Begin transaction
            sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil)
            
            var batchExternalHooks = 0
            var batchInternalHooks = 0
            
            for word in batch {
                let hooks = generateCompleteHooksForWord(word, wordSet: wordSet)
                
                // Insert into database
                sqlite3_bind_text(insertStmt, 1, hooks.word, -1, nil)
                sqlite3_bind_text(insertStmt, 2, hooks.leftExternal, -1, nil)
                sqlite3_bind_text(insertStmt, 3, hooks.rightExternal, -1, nil)
                sqlite3_bind_text(insertStmt, 4, hooks.leftInternal, -1, nil)
                sqlite3_bind_text(insertStmt, 5, hooks.rightInternal, -1, nil)
                
                if sqlite3_step(insertStmt) != SQLITE_DONE {
                    log("❌ Error inserting \(word): \(String(cString: sqlite3_errmsg(db)))")
                }
                sqlite3_reset(insertStmt)
                
                if !hooks.leftExternal.isEmpty || !hooks.rightExternal.isEmpty {
                    batchExternalHooks += 1
                }
                if !hooks.leftInternal.isEmpty || !hooks.rightInternal.isEmpty {
                    batchInternalHooks += 1
                }
                
                totalProcessed += 1
            }
            
            // Commit transaction
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            
            totalWithExternalHooks += batchExternalHooks
            totalWithInternalHooks += batchInternalHooks
            
            // Progress report
            let percentage = Double(totalProcessed) / Double(allWords.count) * 100
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(totalProcessed) / elapsed
            let remaining = Double(allWords.count - totalProcessed) / rate
            let eta = formatTime(remaining)
            
            log("[B\(String(format: "%3d", batchNumber))/\(totalBatches)] \(String(format: "%6d", totalProcessed)) | \(String(format: "%5d", totalWithExternalHooks)) | \(String(format: "%5d", totalWithInternalHooks)) | \(String(format: "%5.1f", percentage))% | \(eta)")
        }
        
        sqlite3_finalize(insertStmt)
        
        // Final verification
        let finalCount = getHooksCount()
        let duration = Date().timeIntervalSince(startTime)
        
        log("────────────────────────────────────────────────────────────────────")
        log("🎉 GENERATION COMPLETED!")
        log("📊 FINAL STATISTICS:")
        log("   • Total words processed: \(totalProcessed)")
        log("   • Words with external hooks: \(totalWithExternalHooks)")
        log("   • Words with internal hooks: \(totalWithInternalHooks)")
        log("   • Database records: \(finalCount)")
        log("   • Total time: \(formatTime(duration))")
        log("   • Processing rate: \(String(format: "%.0f", Double(totalProcessed)/duration)) words/sec")
        
        // Sample results
        log("\n🔍 SAMPLE EXTERNAL HOOKS:")
        showSampleExternalHooks()
        
        log("\n🔍 SAMPLE INTERNAL HOOKS:")
        showSampleInternalHooks()
        
        log("\n✅ Complete hooks generation finished!")
        log("📁 Database: \(dbPath)")
        log("📝 Log file: \(logFile)")
        
        // Notification
        notifyCompletion()
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
    
    private func generateCompleteHooksForWord(_ word: String, wordSet: Set<String>) -> (word: String, leftExternal: String, rightExternal: String, leftInternal: String, rightInternal: String) {
        var leftExternal = ""
        var rightExternal = ""
        var leftInternal = ""
        var rightInternal = ""
        
        // External hooks (extensions)
        for letter in spanishAlphabet {
            // Left external hook: can we add this letter to the left?
            if wordSet.contains(String(letter) + word) {
                leftExternal += String(letter)
            }
            
            // Right external hook: can we add this letter to the right?
            if wordSet.contains(word + String(letter)) {
                rightExternal += String(letter)
            }
        }
        
        // Internal hooks (reductions) - only for words longer than 2 letters
        if word.count > 2 {
            // Left internal hook: if we remove the first letter, does the remaining word exist?
            let withoutFirst = String(word.dropFirst())
            if wordSet.contains(withoutFirst) {
                leftInternal = String(word.first!)
            }
            
            // Right internal hook: if we remove the last letter, does the remaining word exist?
            let withoutLast = String(word.dropLast())
            if wordSet.contains(withoutLast) {
                rightInternal = String(word.last!)
            }
        }
        
        return (word, leftExternal, rightExternal, leftInternal, rightInternal)
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
    
    private func showSampleExternalHooks() {
        let sql = """
        SELECT word, left_hooks, right_hooks
        FROM word_hooks 
        WHERE length(left_hooks) > 2 AND length(right_hooks) > 2
        ORDER BY length(left_hooks) + length(right_hooks) DESC 
        LIMIT 5
        """
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = String(cString: sqlite3_column_text(stmt, 0))
                let left = String(cString: sqlite3_column_text(stmt, 1))
                let right = String(cString: sqlite3_column_text(stmt, 2))
                log("   \(left.lowercased())\(word)\(right.lowercased())")
            }
        }
        
        sqlite3_finalize(stmt)
    }
    
    private func showSampleInternalHooks() {
        let sql = """
        SELECT word, left_internal_hooks, right_internal_hooks
        FROM word_hooks 
        WHERE length(left_internal_hooks) > 0 OR length(right_internal_hooks) > 0
        ORDER BY length(word) DESC 
        LIMIT 5
        """
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = String(cString: sqlite3_column_text(stmt, 0))
                let leftInt = String(cString: sqlite3_column_text(stmt, 1))
                let rightInt = String(cString: sqlite3_column_text(stmt, 2))
                log("   [\(leftInt.lowercased())]\(word)[\(rightInt.lowercased())] -> \(String(word.dropFirst(leftInt.isEmpty ? 0 : 1)))\(String(word.dropLast(rightInt.isEmpty ? 0 : 1)))")
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
    
    private func notifyCompletion() {
        // Create completion file
        let completionFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_hooks_COMPLETED.txt")
        let completionMessage = """
        🎉 HOOKS GENERATION COMPLETED! 🎉
        
        Time: \(Date())
        Database: \(dbPath)
        Log file: \(logFile)
        
        The ScrabbleFinder hooks database is now ready!
        """
        
        try? completionMessage.write(to: URL(fileURLWithPath: completionFile), atomically: true, encoding: .utf8)
        
        // System notification (macOS)
        let _ = Process()
        // Note: We skip the actual notification to avoid permission issues
        
        log("📢 Completion file created: \(completionFile)")
    }
}

// MARK: - Main Execution
func main() {
    print("🔗 ScrabbleFinder COMPLETE Hooks Generator")
    print("==========================================")
    
    let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    do {
        let generator = try CompleteHooksGenerator(dbPath: dbPath)
        generator.generateCompleteHooks()
        
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

main()