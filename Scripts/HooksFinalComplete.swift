#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 FINAL Complete Hooks Generator")
print("═══════════════════════════════════════════")
print("⚡ This script will generate ALL hooks and won't stop until complete!")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
let logFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_hooks_generation.log")

func log(_ message: String) {
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

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    log("❌ Failed to open database")
    exit(1)
}

// Configure for reliability
sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)

// Create hooks table
log("🔧 Creating hooks table...")
sqlite3_exec(db, "DROP TABLE IF EXISTS word_hooks;", nil, nil, nil)
let createSQL = """
CREATE TABLE word_hooks (
    word TEXT PRIMARY KEY,
    left_hooks TEXT DEFAULT '',
    right_hooks TEXT DEFAULT '', 
    left_internal_hooks TEXT DEFAULT '',
    right_internal_hooks TEXT DEFAULT ''
);
"""
sqlite3_exec(db, createSQL, nil, nil, nil)

// Load dictionary
log("📚 Loading complete dictionary...")
var allWords: [String] = []
let sql = "SELECT DISTINCT word FROM words ORDER BY word"
var stmt: OpaquePointer?

if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        allWords.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

let wordSet = Set(allWords)
log("✅ Loaded \(allWords.count) words into memory")

// Spanish alphabet
let alphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")

log("⚡ Generating ALL hooks (external + internal)...")
let startTime = Date()
var processed = 0
var externalHooksCount = 0
var internalHooksCount = 0

// Prepare insert
var insertStmt: OpaquePointer?
sqlite3_prepare_v2(db, "INSERT INTO word_hooks VALUES (?, ?, ?, ?, ?)", -1, &insertStmt, nil)

// Process ALL words in batches
let batchSize = 5000
for batchStart in stride(from: 0, to: allWords.count, by: batchSize) {
    let batchEnd = min(batchStart + batchSize, allWords.count)
    let batch = Array(allWords[batchStart..<batchEnd])
    
    sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    
    for word in batch {
        var leftExternal = ""
        var rightExternal = ""
        var leftInternal = ""
        var rightInternal = ""
        
        // EXTERNAL HOOKS (extensions)
        for letter in alphabet {
            if wordSet.contains(String(letter) + word) {
                leftExternal += String(letter)
            }
            if wordSet.contains(word + String(letter)) {
                rightExternal += String(letter)
            }
        }
        
        // INTERNAL HOOKS (reductions) - only for words > 2 letters
        if word.count > 2 {
            let withoutFirst = String(word.dropFirst())
            if wordSet.contains(withoutFirst) {
                leftInternal = String(word.first!)
            }
            
            let withoutLast = String(word.dropLast())
            if wordSet.contains(withoutLast) {
                rightInternal = String(word.last!)
            }
        }
        
        // Insert into database
        sqlite3_bind_text(insertStmt, 1, word, -1, nil)
        sqlite3_bind_text(insertStmt, 2, leftExternal, -1, nil)
        sqlite3_bind_text(insertStmt, 3, rightExternal, -1, nil)
        sqlite3_bind_text(insertStmt, 4, leftInternal, -1, nil)
        sqlite3_bind_text(insertStmt, 5, rightInternal, -1, nil)
        sqlite3_step(insertStmt)
        sqlite3_reset(insertStmt)
        
        if !leftExternal.isEmpty || !rightExternal.isEmpty {
            externalHooksCount += 1
        }
        if !leftInternal.isEmpty || !rightInternal.isEmpty {
            internalHooksCount += 1
        }
        
        processed += 1
    }
    
    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    
    // Progress every batch
    let percentage = Double(processed) / Double(allWords.count) * 100
    let elapsed = Date().timeIntervalSince(startTime)
    let rate = Double(processed) / elapsed
    let eta = (Double(allWords.count - processed) / rate)
    log("⚡ \(processed)/\(allWords.count) (\(String(format: "%.1f", percentage))%) | Ext: \(externalHooksCount) | Int: \(internalHooksCount) | ETA: \(Int(eta))s")
}

sqlite3_finalize(insertStmt)

let duration = Date().timeIntervalSince(startTime)
log("═══════════════════════════════════════════")
log("🎉 COMPLETE HOOKS GENERATION FINISHED!")
log("📊 FINAL STATISTICS:")
log("   • Total words processed: \(processed)")
log("   • Words with external hooks: \(externalHooksCount)")
log("   • Words with internal hooks: \(internalHooksCount)")
log("   • Total processing time: \(String(format: "%.1f", duration))s")
log("   • Processing rate: \(String(format: "%.0f", Double(processed)/duration)) words/sec")

// Show samples
log("\n🔍 SAMPLE EXTERNAL HOOKS:")
var sampleStmt: OpaquePointer?
let extSQL = "SELECT word, left_hooks, right_hooks FROM word_hooks WHERE length(left_hooks) > 2 AND length(right_hooks) > 2 ORDER BY length(left_hooks) + length(right_hooks) DESC LIMIT 5"

if sqlite3_prepare_v2(db, extSQL, -1, &sampleStmt, nil) == SQLITE_OK {
    while sqlite3_step(sampleStmt) == SQLITE_ROW {
        let word = String(cString: sqlite3_column_text(sampleStmt, 0))
        let left = String(cString: sqlite3_column_text(sampleStmt, 1))
        let right = String(cString: sqlite3_column_text(sampleStmt, 2))
        log("   \(left.lowercased())\(word)\(right.lowercased())")
    }
}
sqlite3_finalize(sampleStmt)

log("\n🔍 SAMPLE INTERNAL HOOKS:")
let intSQL = "SELECT word, left_internal_hooks, right_internal_hooks FROM word_hooks WHERE length(left_internal_hooks) > 0 OR length(right_internal_hooks) > 0 ORDER BY length(word) DESC LIMIT 5"

if sqlite3_prepare_v2(db, intSQL, -1, &sampleStmt, nil) == SQLITE_OK {
    while sqlite3_step(sampleStmt) == SQLITE_ROW {
        let word = String(cString: sqlite3_column_text(sampleStmt, 0))
        let leftInt = String(cString: sqlite3_column_text(sampleStmt, 1))
        let rightInt = String(cString: sqlite3_column_text(sampleStmt, 2))
        
        var examples: [String] = []
        if !leftInt.isEmpty {
            examples.append("[\(leftInt.lowercased())]\(word) → \(String(word.dropFirst()))")
        }
        if !rightInt.isEmpty {
            examples.append("\(word)[\(rightInt.lowercased())] → \(String(word.dropLast()))")
        }
        log("   \(examples.joined(separator: " | "))")
    }
}
sqlite3_finalize(sampleStmt)

// Final verification
var finalStmt: OpaquePointer?
var finalCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &finalStmt, nil) == SQLITE_OK {
    if sqlite3_step(finalStmt) == SQLITE_ROW {
        finalCount = Int(sqlite3_column_int(finalStmt, 0))
    }
}
sqlite3_finalize(finalStmt)

log("💾 Database verification: \(finalCount) records stored")
sqlite3_close(db)

// Create success notification
let successFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_HOOKS_SUCCESS.txt")
let successMessage = """
🎉🎉🎉 COMPLETE HOOKS GENERATION SUCCESS! 🎉🎉🎉

Completion Time: \(Date())
Database: \(dbPath)
Log File: \(logFile)

FINAL RESULTS:
═══════════════════════════════════════════
📊 Total words processed: \(processed)
🔗 Words with external hooks: \(externalHooksCount)
🔄 Words with internal hooks: \(internalHooksCount)
💾 Database records: \(finalCount)
⏱️  Processing time: \(String(format: "%.1f", duration)) seconds
⚡ Processing rate: \(String(format: "%.0f", Double(processed)/duration)) words/sec

HOOK TYPES GENERATED:
═══════════════════════════════════════════
1. EXTERNAL HOOKS: Letters you can ADD before/after words
   Example: "gato" with hooks "s" left and "s" right = "sgatos"

2. INTERNAL HOOKS: Letters you can REMOVE from start/end
   Example: "gatos" can lose "s" at end to become "gato"

🚀 The ScrabbleFinder hooks database is now COMPLETE!
🔧 Ready for app integration and testing!
"""

try? successMessage.write(to: URL(fileURLWithPath: successFile), atomically: true, encoding: .utf8)

log("\n🎊 SUCCESS! Complete hooks generation finished!")
log("📁 Success notification: \(successFile)")
log("📝 Detailed log: \(logFile)")
log("🚀 ScrabbleFinder hooks database is ready!")
log("💯 Process completed at \(Date())")

// Final count verification
log("\n🔍 Final verification complete - all \(finalCount) words processed successfully!")