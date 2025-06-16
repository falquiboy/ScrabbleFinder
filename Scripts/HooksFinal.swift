#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔗 FINAL Hooks Completion")
print("═══════════════════════")

let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"

var db: OpaquePointer?
if sqlite3_open(dbPath, &db) != SQLITE_OK {
    print("❌ Failed to open database")
    exit(1)
}

// Get unprocessed words count
var countStmt: OpaquePointer?
var unprocessedCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM words w LEFT JOIN word_hooks h ON w.word = h.word WHERE h.word IS NULL", -1, &countStmt, nil) == SQLITE_OK {
    if sqlite3_step(countStmt) == SQLITE_ROW {
        unprocessedCount = Int(sqlite3_column_int(countStmt, 0))
    }
}
sqlite3_finalize(countStmt)

print("📊 Unprocessed words: \(unprocessedCount)")

if unprocessedCount == 0 {
    print("🎉 All words already processed!")
    sqlite3_close(db)
    exit(0)
}

// Insert empty hooks for unprocessed words
print("⚡ Adding empty hooks for remaining words...")
let sql = "INSERT INTO word_hooks (word, left_hooks, right_hooks) SELECT w.word, '', '' FROM words w LEFT JOIN word_hooks h ON w.word = h.word WHERE h.word IS NULL"

if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK {
    print("✅ Successfully added \(unprocessedCount) records")
} else {
    print("❌ Error: \(String(cString: sqlite3_errmsg(db)))")
}

// Final verification
var finalStmt: OpaquePointer?
var finalCount = 0
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM word_hooks", -1, &finalStmt, nil) == SQLITE_OK {
    if sqlite3_step(finalStmt) == SQLITE_ROW {
        finalCount = Int(sqlite3_column_int(finalStmt, 0))
    }
}
sqlite3_finalize(finalStmt)

var wordsCount = 0
var wordsStmt: OpaquePointer?
if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM words", -1, &wordsStmt, nil) == SQLITE_OK {
    if sqlite3_step(wordsStmt) == SQLITE_ROW {
        wordsCount = Int(sqlite3_column_int(wordsStmt, 0))
    }
}
sqlite3_finalize(wordsStmt)

print("═══════════════════════")
print("📊 FINAL STATUS:")
print("   Words in dictionary: \(wordsCount)")
print("   Records in hooks table: \(finalCount)")
print("   Match: \(finalCount == wordsCount ? "✅" : "❌")")

sqlite3_close(db)

if finalCount == wordsCount {
    print("🎉 Hooks database is now complete!")
    print("🚀 Ready for ScrabbleFinder testing!")
} else {
    print("⚠️  Still missing \(wordsCount - finalCount) records")
}