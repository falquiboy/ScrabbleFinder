#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 VERIFIED Hooks Generator - Starting NOW!")
print("═══════════════════════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

// Open database
var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

// Configure for immediate persistence
sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)

// Clear and recreate table
print("🗑️  Clearing existing hooks table...")
sqlite3_exec(db, "DROP TABLE IF EXISTS word_hooks;", nil, nil, nil)
sqlite3_exec(db, "CREATE TABLE word_hooks (word TEXT PRIMARY KEY, left_hooks TEXT, right_hooks TEXT);", nil, nil, nil)

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

// Spanish alphabet
let alphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")

print("⚡ Generating hooks...")
var processed = 0
var hooksFound = 0
let startTime = Date()

// Use individual INSERT statements for maximum reliability
for word in allWords {
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
    
    // Insert into database with immediate verification
    let insertSQL = "INSERT INTO word_hooks VALUES ('\(word)', '\(leftHooks)', '\(rightHooks)')"
    if sqlite3_exec(db, insertSQL, nil, nil, nil) != SQLITE_OK {
        print("❌ Failed to insert \(word): \(String(cString: sqlite3_errmsg(db)))")
    }
    
    if !leftHooks.isEmpty || !rightHooks.isEmpty {
        hooksFound += 1
    }
    
    processed += 1
    
    // Progress every 10,000 words with verification
    if processed % 10000 == 0 {
        // Verify current count in database
        var verifyStmt: OpaquePointer?
        var dbCount = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &verifyStmt, nil) == SQLITE_OK {
            if sqlite3_step(verifyStmt) == SQLITE_ROW {
                dbCount = Int(sqlite3_column_int(verifyStmt, 0))
            }
        }
        sqlite3_finalize(verifyStmt)
        
        let percentage = Double(processed) / Double(allWords.count) * 100
        let elapsed = Date().timeIntervalSince(startTime)
        let rate = Double(processed) / elapsed
        let eta = (Double(allWords.count - processed) / rate)
        print("⚡ \(processed)/\(allWords.count) (\(String(format: "%.1f", percentage))%) | DB: \(dbCount) | Hooks: \(hooksFound) | ETA: \(Int(eta))s")
    }
}

let duration = Date().timeIntervalSince(startTime)

// Final verification
var finalStmt: OpaquePointer?
var finalCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &finalStmt, nil) == SQLITE_OK {
    if sqlite3_step(finalStmt) == SQLITE_ROW {
        finalCount = Int(sqlite3_column_int(finalStmt, 0))
    }
}
sqlite3_finalize(finalStmt)

print("═══════════════════════════════════════════")
print("🎉 COMPLETED!")
print("📊 Words processed: \(processed)")
print("🔗 Words with hooks: \(hooksFound)")
print("💾 Database records: \(finalCount)")
print("⏱️  Time: \(String(format: "%.1f", duration))s")
print("⚡ Rate: \(String(format: "%.0f", Double(processed)/duration)) words/sec")

// Show sample results
print("\n🔍 Sample results:")
var sampleStmt: OpaquePointer?
let sampleSQL = "SELECT word, left_hooks, right_hooks FROM word_hooks WHERE length(left_hooks) > 0 OR length(right_hooks) > 0 ORDER BY length(left_hooks) + length(right_hooks) DESC LIMIT 10"

if sqlite3_prepare_v2(db, sampleSQL, -1, &sampleStmt, nil) == SQLITE_OK {
    while sqlite3_step(sampleStmt) == SQLITE_ROW {
        let word = String(cString: sqlite3_column_text(sampleStmt, 0))
        let left = String(cString: sqlite3_column_text(sampleStmt, 1))
        let right = String(cString: sqlite3_column_text(sampleStmt, 2))
        print("   \(left.lowercased())\(word)\(right.lowercased())")
    }
}

sqlite3_finalize(sampleStmt)
sqlite3_close(db)

if finalCount == processed {
    print("\n✅ SUCCESS: All \(finalCount) records verified in database!")
} else {
    print("\n⚠️  WARNING: Expected \(processed) but found \(finalCount) in database")
}

print("🚀 Ready to test in ScrabbleFinder app!")