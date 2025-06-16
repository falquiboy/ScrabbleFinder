#!/usr/bin/env swift

import Foundation
import SQLite3

// MARK: - Data Structures
struct WordHooks {
    let word: String
    let leftHooks: [Character]
    let rightHooks: [Character]
    
    var leftHooksString: String {
        return String(leftHooks.sorted())
    }
    
    var rightHooksString: String {
        return String(rightHooks.sorted())
    }
}

// MARK: - Hooks Generator
class HooksGenerator {
    private var db: OpaquePointer?
    private let spanishAlphabet = Array("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")
    
    init(dbPath: String) throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw NSError(domain: "HooksGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
        
        // Create hooks table if it doesn't exist
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
        
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("❌ Error creating hooks table: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("✅ Hooks table created/verified")
        }
    }
    
    func generateAllHooks() {
        print("🚀 Starting hooks generation...")
        
        // Get all words from database
        let words = getAllWords()
        print("📚 Found \(words.count) words in database")
        
        // Create word set for fast lookup
        let wordSet = Set(words)
        
        var processedCount = 0
        let totalWords = words.count
        
        // Generate hooks for each word
        for word in words {
            let hooks = generateHooksForWord(word, wordSet: wordSet)
            saveHooks(hooks)
            
            processedCount += 1
            if processedCount % 1000 == 0 {
                let percentage = (Double(processedCount) / Double(totalWords)) * 100
                print("⏳ Progress: \(processedCount)/\(totalWords) (\(String(format: "%.1f", percentage))%)")
            }
        }
        
        print("🎉 Hooks generation completed! Processed \(processedCount) words")
    }
    
    private func getAllWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT DISTINCT word FROM words ORDER BY word"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    let word = String(cString: cString)
                    words.append(word)
                }
            }
        } else {
            print("❌ Error preparing statement: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(stmt)
        return words
    }
    
    private func generateHooksForWord(_ word: String, wordSet: Set<String>) -> WordHooks {
        var leftHooks: [Character] = []
        var rightHooks: [Character] = []
        
        // Test each letter of the alphabet
        for letter in spanishAlphabet {
            // Test left hook: letter + word
            let leftCandidate = String(letter) + word
            if wordSet.contains(leftCandidate) {
                leftHooks.append(letter)
            }
            
            // Test right hook: word + letter
            let rightCandidate = word + String(letter)
            if wordSet.contains(rightCandidate) {
                rightHooks.append(letter)
            }
        }
        
        return WordHooks(word: word, leftHooks: leftHooks, rightHooks: rightHooks)
    }
    
    private func saveHooks(_ hooks: WordHooks) {
        let sql = """
        INSERT OR REPLACE INTO word_hooks (word, left_hooks, right_hooks) 
        VALUES (?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, hooks.word, -1, nil)
            sqlite3_bind_text(stmt, 2, hooks.leftHooksString, -1, nil)
            sqlite3_bind_text(stmt, 3, hooks.rightHooksString, -1, nil)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("❌ Error inserting hooks for \(hooks.word): \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(stmt)
    }
}

// MARK: - Main Execution
func main() {
    print("🔧 ScrabbleFinder Hooks Generator")
    print("================================")
    
    // Path to your SQLite database
    let dbPath = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    do {
        let generator = try HooksGenerator(dbPath: dbPath)
        generator.generateAllHooks()
        print("✅ All done! Hooks have been added to your database.")
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

main()