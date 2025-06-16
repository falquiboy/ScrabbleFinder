#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 ROBUST Hooks Generator with Real-time Verification")
print("════════════════════════════════════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

// ULTRA CONSERVATIVE settings for maximum persistence
sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous=FULL;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA locking_mode=EXCLUSIVE;", nil, nil, nil)

// Start fresh
print("🗑️  Dropping existing hooks table...")
sqlite3_exec(db, "DROP TABLE IF EXISTS word_hooks;", nil, nil, nil)

print("🔧 Creating new hooks table...")
let createSQL = """
CREATE TABLE word_hooks (
    word TEXT PRIMARY KEY,
    left_hooks TEXT NOT NULL DEFAULT '',
    right_hooks TEXT NOT NULL DEFAULT '',
    left_internal_hooks TEXT NOT NULL DEFAULT '',
    right_internal_hooks TEXT NOT NULL DEFAULT ''
);
"""

if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
    print("❌ Failed to create table: \(String(cString: sqlite3_errmsg(db)))")
    exit(1)
}

// Test the table immediately
var testStmt: OpaquePointer?
if sqlite3_prepare_v2(db, "INSERT INTO word_hooks VALUES ('TEST', 'A', 'B', 'C', 'D')", -1, &testStmt, nil) == SQLITE_OK {
    if sqlite3_step(testStmt) == SQLITE_DONE {
        print("✅ Table creation verified")
    } else {
        print("❌ Table test failed")
        exit(1)
    }
}
sqlite3_finalize(testStmt)

// Remove test record
sqlite3_exec(db, "DELETE FROM word_hooks WHERE word = 'TEST';", nil, nil, nil)

// Load dictionary
print("📚 Loading dictionary...")
var allWords: [String] = []
let sql = "SELECT DISTINCT word FROM words ORDER BY word LIMIT 1000"  // Start with 1000 words for testing
var stmt: OpaquePointer?

if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
    while sqlite3_step(stmt) == SQLITE_ROW {
        allWords.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
}
sqlite3_finalize(stmt)

let wordSet = Set(allWords)
print("✅ Loaded \(allWords.count) words for processing")

// Spanish alphabet
let alphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")

print("⚡ Generating hooks with AGGRESSIVE verification...")
let startTime = Date()
var processed = 0
var actuallyStored = 0

// Process word by word with immediate verification
for (index, word) in allWords.enumerated() {
    var leftExternal = ""
    var rightExternal = ""
    var leftInternal = ""
    var rightInternal = ""
    
    // Generate external hooks
    for letter in alphabet {
        if wordSet.contains(String(letter) + word) {
            leftExternal += String(letter)
        }
        if wordSet.contains(word + String(letter)) {
            rightExternal += String(letter)
        }
    }
    
    // Generate internal hooks (for words > 2 letters)
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
    
    // Insert IMMEDIATELY with verification
    let insertSQL = """
    INSERT INTO word_hooks (word, left_hooks, right_hooks, left_internal_hooks, right_internal_hooks) 
    VALUES ('\(word)', '\(leftExternal)', '\(rightExternal)', '\(leftInternal)', '\(rightInternal)')
    """
    
    if sqlite3_exec(db, insertSQL, nil, nil, nil) == SQLITE_OK {
        // Immediately verify the record was stored
        var verifyStmt: OpaquePointer?
        var found = false
        let verifySQL = "SELECT word FROM word_hooks WHERE word = '\(word)'"
        
        if sqlite3_prepare_v2(db, verifySQL, -1, &verifyStmt, nil) == SQLITE_OK {
            if sqlite3_step(verifyStmt) == SQLITE_ROW {
                found = true
                actuallyStored += 1
            }
        }
        sqlite3_finalize(verifyStmt)
        
        if !found {
            print("⚠️  WARNING: Record for '\(word)' not found after insert!")
        }
        
    } else {
        print("❌ Error inserting '\(word)': \(String(cString: sqlite3_errmsg(db)))")
    }
    
    processed += 1
    
    // Progress every 100 words with live verification
    if processed % 100 == 0 {
        var countStmt: OpaquePointer?
        var dbCount = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                dbCount = Int(sqlite3_column_int(countStmt, 0))
            }
        }
        sqlite3_finalize(countStmt)
        
        let percentage = Double(processed) / Double(allWords.count) * 100
        print("⚡ \(processed)/\(allWords.count) (\(String(format: "%.1f", percentage))%) | DB: \(dbCount) | Verified: \(actuallyStored)")
        
        if dbCount != actuallyStored {
            print("🚨 MISMATCH: DB shows \(dbCount) but verified \(actuallyStored)!")
        }
    }
}

let duration = Date().timeIntervalSince(startTime)

// Final comprehensive verification
var finalStmt: OpaquePointer?
var finalCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &finalStmt, nil) == SQLITE_OK {
    if sqlite3_step(finalStmt) == SQLITE_ROW {
        finalCount = Int(sqlite3_column_int(finalStmt, 0))
    }
}
sqlite3_finalize(finalStmt)

print("════════════════════════════════════════════════════")
print("🎯 ROBUST PROCESSING COMPLETED!")
print("📊 Words processed: \(processed)")
print("✅ Records verified during insert: \(actuallyStored)")
print("💾 Final database count: \(finalCount)")
print("⏱️  Time: \(String(format: "%.1f", duration))s")

if finalCount == processed && finalCount == actuallyStored {
    print("🎉 SUCCESS: All records match!")
    
    // Show some sample data
    print("\n🔍 Sample records:")
    var sampleStmt: OpaquePointer?
    let sampleSQL = "SELECT word, left_hooks, right_hooks, left_internal_hooks, right_internal_hooks FROM word_hooks LIMIT 5"
    
    if sqlite3_prepare_v2(db, sampleSQL, -1, &sampleStmt, nil) == SQLITE_OK {
        while sqlite3_step(sampleStmt) == SQLITE_ROW {
            let word = String(cString: sqlite3_column_text(sampleStmt, 0))
            let leftExt = String(cString: sqlite3_column_text(sampleStmt, 1))
            let rightExt = String(cString: sqlite3_column_text(sampleStmt, 2))
            let leftInt = String(cString: sqlite3_column_text(sampleStmt, 3))
            let rightInt = String(cString: sqlite3_column_text(sampleStmt, 4))
            
            print("   \(word): ext(\(leftExt)|\(rightExt)) int(\(leftInt)|\(rightInt))")
        }
    }
    sqlite3_finalize(sampleStmt)
    
} else {
    print("❌ FAILURE: Count mismatch - investigation needed!")
}

sqlite3_close(db)

if finalCount == processed {
    print("\n🚀 Ready to scale up to full dictionary!")
} else {
    print("\n🔧 Need to fix persistence issues before scaling up")
}