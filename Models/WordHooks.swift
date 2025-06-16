import Foundation
import SQLite3

// MARK: - Word Hooks Data Structure
struct WordHooks {
    let word: String
    let leftHooks: [Character]
    let rightHooks: [Character]
    
    var hasHooks: Bool {
        return !leftHooks.isEmpty || !rightHooks.isEmpty
    }
    
    var leftHooksString: String {
        return leftHooks.isEmpty ? "" : String(leftHooks.sorted())
    }
    
    var rightHooksString: String {
        return rightHooks.isEmpty ? "" : String(rightHooks.sorted())
    }
    
    /// Pretty formatted hooks for display: "bCASAl" or just "CASA" if no hooks
    var formattedDisplay: String {
        let leftPart = leftHooks.isEmpty ? "" : leftHooksString.lowercased()
        let rightPart = rightHooks.isEmpty ? "" : rightHooksString.lowercased()
        return leftPart + word + rightPart
    }
}

// MARK: - Hooks Cache Manager
class HooksManager {
    private var hooksCache: [String: WordHooks] = [:]
    private var db: OpaquePointer?
    
    init(database: OpaquePointer?) {
        self.db = database
    }
    
    /// Get hooks for a specific word
    func getHooks(for word: String) -> WordHooks? {
        // Check cache first
        if let cached = hooksCache[word] {
            return cached
        }
        
        // Load from database
        guard let db = db else { return nil }
        
        let sql = "SELECT left_hooks, right_hooks FROM word_hooks WHERE word = ? LIMIT 1"
        var stmt: OpaquePointer?
        var hooks: WordHooks?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, word, -1, nil)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let leftHooksStr = String(cString: sqlite3_column_text(stmt, 0))
                let rightHooksStr = String(cString: sqlite3_column_text(stmt, 1))
                
                let leftHooks = Array(leftHooksStr)
                let rightHooks = Array(rightHooksStr)
                
                hooks = WordHooks(word: word, leftHooks: leftHooks, rightHooks: rightHooks)
                
                // Cache the result
                hooksCache[word] = hooks
            }
        }
        
        sqlite3_finalize(stmt)
        return hooks
    }
    
    /// Batch load hooks for multiple words
    func getHooks(for words: [String]) -> [String: WordHooks] {
        var result: [String: WordHooks] = [:]
        
        for word in words {
            if let hooks = getHooks(for: word) {
                result[word] = hooks
            }
        }
        
        return result
    }
    
    /// Clear the cache (useful for memory management)
    func clearCache() {
        hooksCache.removeAll()
    }
}