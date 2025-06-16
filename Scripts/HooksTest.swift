#!/usr/bin/env swift

import Foundation
import SQLite3

class HooksTest {
    private var db: OpaquePointer?
    private let spanishAlphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")
    
    init(dbPath: String) throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw NSError(domain: "HooksTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        
        createHooksTable()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func createHooksTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS word_hooks (
            word TEXT PRIMARY KEY,
            left_hooks TEXT,
            right_hooks TEXT
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    func testHooksGeneration() {
        print("🧪 Testing hooks generation with sample words...")
        
        // Get first 100 words
        let words = getTestWords()
        let wordSet = Set(getAllWords()) // Full set for lookup
        
        print("📚 Testing with \(words.count) words")
        print("🔍 Full dictionary has \(wordSet.count) words for lookup")
        
        for word in words {
            let hooks = generateHooksForWord(word, wordSet: wordSet)
            saveHooks(hooks)
            
            if !hooks.left.isEmpty || !hooks.right.isEmpty {
                print("✅ \(word): left='\(hooks.left)' right='\(hooks.right)'")
            }
        }
        
        // Check results
        let count = getHooksCount()
        print("🎉 Generated hooks for \(count) words")
    }
    
    private func getTestWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT DISTINCT word FROM words ORDER BY word LIMIT 100"
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
    
    private func getAllWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT DISTINCT word FROM words"
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
            let leftCandidate = String(letter) + word
            if wordSet.contains(leftCandidate) {
                leftHooks += String(letter)
                print("🔗 Found left hook: \(letter) + \(word) = \(leftCandidate)")
            }
            
            // Test right hook
            let rightCandidate = word + String(letter)
            if wordSet.contains(rightCandidate) {
                rightHooks += String(letter)
                print("🔗 Found right hook: \(word) + \(letter) = \(rightCandidate)")
            }
        }
        
        return (word, leftHooks, rightHooks)
    }
    
    private func saveHooks(_ hooks: (word: String, left: String, right: String)) {
        let sql = "INSERT OR REPLACE INTO word_hooks (word, left_hooks, right_hooks) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, hooks.word, -1, nil)
            sqlite3_bind_text(stmt, 2, hooks.left, -1, nil)
            sqlite3_bind_text(stmt, 3, hooks.right, -1, nil)
            sqlite3_step(stmt)
        }
        
        sqlite3_finalize(stmt)
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
}

// MARK: - Main
func main() {
    let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    do {
        let tester = try HooksTest(dbPath: dbPath)
        tester.testHooksGeneration()
    } catch {
        print("❌ Error: \(error)")
    }
}

main()