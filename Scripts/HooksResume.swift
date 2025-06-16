#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 RESUMING Hooks Generator")
print("═══════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

// Configure for reliability
sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)

// Get words that haven't been processed yet
print("📚 Finding unprocessed words...")
var unprocessedWords: [String] = []
let sql = """
SELECT DISTINCT w.word 
FROM words w 
LEFT JOIN word_hooks h ON w.word = h.word 
WHERE h.word IS NULL 
ORDER BY w.word
"""
var stmt: OpaquePointer?

if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        unprocessedWords.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

print("✅ Found \(unprocessedWords.count) unprocessed words")

if unprocessedWords.isEmpty {
    print("🎉 All words already processed!")
    sqlite3_close(db)
    exit(0)
}

// Load all words for lookup
print("📖 Loading full dictionary for lookup...")
var allWords: [String] = []
let allWordsSQL = "SELECT DISTINCT word FROM words"
if sqlite3_prepare_v2(db, allWordsSQL, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        allWords.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

let wordSet = Set(allWords)
print("✅ Dictionary ready with \(wordSet.count) words")

// Spanish alphabet
let alphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")

print("⚡ Processing remaining \(unprocessedWords.count) words...")
var processed = 0
var hooksFound = 0
let startTime = Date()

// Process in batches for better performance
let batchSize = 1000
var insertStmt: OpaquePointer?
sqlite3_prepare_v2(db, "INSERT INTO word_hooks VALUES (?, ?, ?)", -1, &insertStmt, nil)

for batch in stride(from: 0, to: unprocessedWords.count, by: batchSize) {
    let endIndex = min(batch + batchSize, unprocessedWords.count)
    let currentBatch = Array(unprocessedWords[batch..<endIndex])
    
    sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    
    for word in currentBatch {
        var leftHooks = ""
        var rightHooks = ""
        
        // Find left hooks
        for letter in alphabet {
            if wordSet.contains(String(letter) + word) {
                leftHooks += String(letter)
            }
        }
        
        // Find right hooks
        for letter in alphabet {
            if wordSet.contains(word + String(letter)) {
                rightHooks += String(letter)
            }
        }
        
        // Insert
        sqlite3_bind_text(insertStmt, 1, word, -1, nil)
        sqlite3_bind_text(insertStmt, 2, leftHooks, -1, nil)
        sqlite3_bind_text(insertStmt, 3, rightHooks, -1, nil)
        sqlite3_step(insertStmt)
        sqlite3_reset(insertStmt)
        
        if !leftHooks.isEmpty || !rightHooks.isEmpty {
            hooksFound += 1
        }
        
        processed += 1
    }
    
    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    
    // Progress report
    let percentage = Double(processed) / Double(unprocessedWords.count) * 100
    let elapsed = Date().timeIntervalSince(startTime)
    let rate = Double(processed) / elapsed
    let eta = (Double(unprocessedWords.count - processed) / rate)
    print("⚡ \(processed)/\(unprocessedWords.count) (\(String(format: "%.1f", percentage))%) | \(hooksFound) hooks | ETA: \(Int(eta))s")
}

sqlite3_finalize(insertStmt)

let duration = Date().timeIntervalSince(startTime)

// Final count
var finalStmt: OpaquePointer?
var finalCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &finalStmt, nil) == SQLITE_OK {
    if sqlite3_step(finalStmt) == SQLITE_ROW {
        finalCount = Int(sqlite3_column_int(finalStmt, 0))
    }
}
sqlite3_finalize(finalStmt)

print("═══════════════════════════════════════════")
print("🎉 RESUME COMPLETED!")
print("📊 Additional words processed: \(processed)")
print("🔗 Additional hooks found: \(hooksFound)")
print("💾 Total database records: \(finalCount)")
print("⏱️  Time: \(String(format: "%.1f", duration))s")

sqlite3_close(db)
print("✅ Hooks generation complete!")