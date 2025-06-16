#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 Simple Hooks Generator - Starting NOW!")
print("═══════════════════════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

// Open database
var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

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

// Prepare insert statement
var insertStmt: OpaquePointer?
sqlite3_prepare_v2(db, "INSERT INTO word_hooks VALUES (?, ?, ?)", -1, &insertStmt, nil)

print("⚡ Generating hooks...")
var processed = 0
var hooksFound = 0
let startTime = Date()

sqlite3_exec(db, "BEGIN;", nil, nil, nil)

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
    
    // Insert into database
    sqlite3_bind_text(insertStmt, 1, word, -1, nil)
    sqlite3_bind_text(insertStmt, 2, leftHooks, -1, nil)
    sqlite3_bind_text(insertStmt, 3, rightHooks, -1, nil)
    sqlite3_step(insertStmt)
    sqlite3_reset(insertStmt)
    
    if !leftHooks.isEmpty || !rightHooks.isEmpty {
        hooksFound += 1
    }
    
    processed += 1
    
    // Progress every 10,000 words
    if processed % 10000 == 0 {
        let percentage = Double(processed) / Double(allWords.count) * 100
        let elapsed = Date().timeIntervalSince(startTime)
        let rate = Double(processed) / elapsed
        let eta = (Double(allWords.count - processed) / rate)
        print("⚡ \(processed)/\(allWords.count) (\(String(format: "%.1f", percentage))%) | \(hooksFound) hooks | ETA: \(Int(eta))s")
    }
}

sqlite3_exec(db, "COMMIT;", nil, nil, nil)
sqlite3_finalize(insertStmt)

let duration = Date().timeIntervalSince(startTime)
print("═══════════════════════════════════════════")
print("🎉 COMPLETED!")
print("📊 Words processed: \(processed)")
print("🔗 Words with hooks: \(hooksFound)")
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

print("\n✅ Hooks generation complete!")
print("🚀 Ready to test in ScrabbleFinder app!")