#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 Complete Internal Hooks Generator")
print("═══════════════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)

// Load all words
print("📚 Loading dictionary...")
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
print("✅ Loaded \(allWords.count) words")

// Get all words from hooks table that need internal hooks
print("🔍 Getting words from hooks table...")
var hooksWords: [String] = []
let hooksSQL = "SELECT word FROM word_hooks WHERE length(word) > 2 ORDER BY word"
if sqlite3_prepare_v2(db, hooksSQL, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        hooksWords.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

print("✅ Found \(hooksWords.count) words with length > 2")

print("⚡ Processing internal hooks...")
var processed = 0
var hooksFound = 0
let startTime = Date()

// Prepare update statement
var updateStmt: OpaquePointer?
sqlite3_prepare_v2(db, "UPDATE word_hooks SET left_internal_hooks = ?, right_internal_hooks = ? WHERE word = ?", -1, &updateStmt, nil)

// Process in batches
let batchSize = 2000
for batch in stride(from: 0, to: hooksWords.count, by: batchSize) {
    let endIndex = min(batch + batchSize, hooksWords.count)
    let currentBatch = Array(hooksWords[batch..<endIndex])
    
    sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    
    for word in currentBatch {
        var leftInternal = ""
        var rightInternal = ""
        
        // Left internal: remove first letter, check if remaining word exists
        let withoutFirst = String(word.dropFirst())
        if wordSet.contains(withoutFirst) {
            leftInternal = String(word.first!)
        }
        
        // Right internal: remove last letter, check if remaining word exists  
        let withoutLast = String(word.dropLast())
        if wordSet.contains(withoutLast) {
            rightInternal = String(word.last!)
        }
        
        // Update database
        sqlite3_bind_text(updateStmt, 1, leftInternal, -1, nil)
        sqlite3_bind_text(updateStmt, 2, rightInternal, -1, nil)
        sqlite3_bind_text(updateStmt, 3, word, -1, nil)
        sqlite3_step(updateStmt)
        sqlite3_reset(updateStmt)
        
        if !leftInternal.isEmpty || !rightInternal.isEmpty {
            hooksFound += 1
        }
        
        processed += 1
    }
    
    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    
    // Progress every batch
    let percentage = Double(processed) / Double(hooksWords.count) * 100
    let elapsed = Date().timeIntervalSince(startTime)
    let rate = Double(processed) / elapsed
    let eta = (Double(hooksWords.count - processed) / rate)
    print("⚡ \(processed)/\(hooksWords.count) (\(String(format: "%.1f", percentage))%) | \(hooksFound) hooks | ETA: \(Int(eta))s")
}

sqlite3_finalize(updateStmt)

let duration = Date().timeIntervalSince(startTime)
print("═══════════════════════════════════════════")
print("🎉 INTERNAL HOOKS COMPLETED!")
print("📊 Words processed: \(processed)")
print("🔗 Words with internal hooks: \(hooksFound)")
print("⏱️  Time: \(String(format: "%.1f", duration))s")
print("📈 Success rate: \(String(format: "%.1f", Double(hooksFound)/Double(processed)*100))%")

// Show comprehensive sample
print("\n🔍 Sample internal hooks:")
var sampleStmt: OpaquePointer?
let sampleSQL = """
SELECT word, left_internal_hooks, right_internal_hooks 
FROM word_hooks 
WHERE length(left_internal_hooks) > 0 OR length(right_internal_hooks) > 0
ORDER BY length(word) DESC 
LIMIT 15
"""

if sqlite3_prepare_v2(db, sampleSQL, -1, &sampleStmt, nil) == SQLITE_OK {
    while sqlite3_step(sampleStmt) == SQLITE_ROW {
        let word = String(cString: sqlite3_column_text(sampleStmt, 0))
        let leftInt = String(cString: sqlite3_column_text(sampleStmt, 1))
        let rightInt = String(cString: sqlite3_column_text(sampleStmt, 2))
        
        var display = word
        if !leftInt.isEmpty {
            display += " → [\(leftInt.lowercased())]\(String(word.dropFirst()))"
        }
        if !rightInt.isEmpty {
            if !leftInt.isEmpty { display += " | " }
            display += " → \(String(word.dropLast()))[\(rightInt.lowercased())]"
        }
        print("   \(display)")
    }
}

sqlite3_finalize(sampleStmt)

// Final stats
var statsStmt: OpaquePointer?
var totalHooks = 0
var externalHooks = 0
var internalHooks = 0

if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &statsStmt, nil) == SQLITE_OK {
    if sqlite3_step(statsStmt) == SQLITE_ROW {
        totalHooks = Int(sqlite3_column_int(statsStmt, 0))
    }
}
sqlite3_finalize(statsStmt)

if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks WHERE length(left_hooks) > 0 OR length(right_hooks) > 0", -1, &statsStmt, nil) == SQLITE_OK {
    if sqlite3_step(statsStmt) == SQLITE_ROW {
        externalHooks = Int(sqlite3_column_int(statsStmt, 0))
    }
}
sqlite3_finalize(statsStmt)

if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks WHERE length(left_internal_hooks) > 0 OR length(right_internal_hooks) > 0", -1, &statsStmt, nil) == SQLITE_OK {
    if sqlite3_step(statsStmt) == SQLITE_ROW {
        internalHooks = Int(sqlite3_column_int(statsStmt, 0))
    }
}
sqlite3_finalize(statsStmt)

print("\n📊 FINAL DATABASE STATS:")
print("   • Total words in hooks table: \(totalHooks)")
print("   • Words with external hooks: \(externalHooks)")
print("   • Words with internal hooks: \(internalHooks)")

sqlite3_close(db)

// Create completion notification
let completionFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_HOOKS_ALL_COMPLETED.txt")
let message = """
🎉 COMPLETE HOOKS GENERATION FINISHED! 🎉

Timestamp: \(Date())

RESULTS:
- Total words: \(totalHooks)
- External hooks: \(externalHooks) words
- Internal hooks: \(internalHooks) words
- Processing time: \(String(format: "%.1f", duration))s

HOOKS TYPES:
1. External hooks (extensions): Letters you can ADD before/after word
2. Internal hooks (reductions): Letters you can REMOVE from start/end if remaining word is valid

The ScrabbleFinder hooks database is now COMPLETE!
Ready for integration and testing.
"""

try? message.write(to: URL(fileURLWithPath: completionFile), atomically: true, encoding: .utf8)

print("\n✅ Complete hooks generation finished!")
print("📁 Notification: \(completionFile)")
print("🚀 Database ready for ScrabbleFinder testing!")

// Sound notification (macOS)
print("🔔 Process completed!")