#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 Hooks Internos Generator - Starting NOW!")
print("═══════════════════════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

// Open database
var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

// Configure for reliability  
sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)

// Add new columns for internal hooks if they don't exist
print("🔧 Adding internal hooks columns...")
sqlite3_exec(db, "ALTER TABLE word_hooks ADD COLUMN left_internal_hooks TEXT DEFAULT '';", nil, nil, nil)
sqlite3_exec(db, "ALTER TABLE word_hooks ADD COLUMN right_internal_hooks TEXT DEFAULT '';", nil, nil, nil)

// Load all words into memory for fast lookup
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

// Get words that need internal hooks processing
print("🔍 Finding words to process...")
var wordsToProcess: [String] = []
let checkSQL = "SELECT word FROM word_hooks WHERE length(word) > 2 AND (left_internal_hooks = '' AND right_internal_hooks = '')"
if sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        wordsToProcess.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

print("✅ Found \(wordsToProcess.count) words to process")

print("⚡ Generating internal hooks...")
var processed = 0
var hooksFound = 0
let startTime = Date()

// Prepare update statement
var updateStmt: OpaquePointer?
sqlite3_prepare_v2(db, "UPDATE word_hooks SET left_internal_hooks = ?, right_internal_hooks = ? WHERE word = ?", -1, &updateStmt, nil)

// Process in batches
let batchSize = 1000
for batch in stride(from: 0, to: wordsToProcess.count, by: batchSize) {
    let endIndex = min(batch + batchSize, wordsToProcess.count)
    let currentBatch = Array(wordsToProcess[batch..<endIndex])
    
    sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    
    for word in currentBatch {
        var leftInternal = ""
        var rightInternal = ""
        
        // Left internal hook: if we remove the first letter, does the word exist?
        if word.count > 2 {
            let withoutFirst = String(word.dropFirst())
            if wordSet.contains(withoutFirst) {
                leftInternal = String(word.first!)
            }
            
            // Right internal hook: if we remove the last letter, does the word exist?
            let withoutLast = String(word.dropLast())
            if wordSet.contains(withoutLast) {
                rightInternal = String(word.last!)
            }
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
    
    // Progress
    let percentage = Double(processed) / Double(wordsToProcess.count) * 100
    let elapsed = Date().timeIntervalSince(startTime)
    let rate = Double(processed) / elapsed
    let eta = (Double(wordsToProcess.count - processed) / rate)
    print("⚡ \(processed)/\(wordsToProcess.count) (\(String(format: "%.1f", percentage))%) | \(hooksFound) internal hooks | ETA: \(Int(eta))s")
}

sqlite3_finalize(updateStmt)

let duration = Date().timeIntervalSince(startTime)
print("═══════════════════════════════════════════")
print("🎉 INTERNAL HOOKS COMPLETED!")
print("📊 Words processed: \(processed)")
print("🔗 Words with internal hooks: \(hooksFound)")
print("⏱️  Time: \(String(format: "%.1f", duration))s")

// Show sample internal hooks
print("\n🔍 Sample internal hooks:")
var sampleStmt: OpaquePointer?
let sampleSQL = """
SELECT word, left_internal_hooks, right_internal_hooks 
FROM word_hooks 
WHERE length(left_internal_hooks) > 0 OR length(right_internal_hooks) > 0
ORDER BY length(word) DESC 
LIMIT 10
"""

if sqlite3_prepare_v2(db, sampleSQL, -1, &sampleStmt, nil) == SQLITE_OK {
    while sqlite3_step(sampleStmt) == SQLITE_ROW {
        let word = String(cString: sqlite3_column_text(sampleStmt, 0))
        let leftInt = String(cString: sqlite3_column_text(sampleStmt, 1))
        let rightInt = String(cString: sqlite3_column_text(sampleStmt, 2))
        
        var display = ""
        if !leftInt.isEmpty {
            display += "[\(leftInt.lowercased())]\(word) → \(String(word.dropFirst()))"
        }
        if !rightInt.isEmpty {
            if !display.isEmpty { display += " | " }
            display += "\(word)[\(rightInt.lowercased())] → \(String(word.dropLast()))"
        }
        print("   \(display)")
    }
}

sqlite3_finalize(sampleStmt)
sqlite3_close(db)

// Final verification
let completionFile = dbPath.replacingOccurrences(of: ".sqlite", with: "_internal_hooks_COMPLETED.txt")
let message = """
🎉 INTERNAL HOOKS GENERATION COMPLETED! 🎉

Time: \(Date())
Words processed: \(processed)
Internal hooks found: \(hooksFound)
Processing time: \(String(format: "%.1f", duration))s

Database now contains both external and internal hooks!
"""

try? message.write(to: URL(fileURLWithPath: completionFile), atomically: true, encoding: .utf8)

print("\n✅ Internal hooks generation complete!")
print("📁 Completion file: \(completionFile)")
print("🚀 Ready to test complete hooks in ScrabbleFinder!")