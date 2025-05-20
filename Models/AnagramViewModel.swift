import Foundation
import SQLite3

struct ExtraLetterWord: Identifiable {
    let id = UUID()
    let word: String
    let extraLetter: Character
}

/// ViewModel for fetching anagrams from the bundled SQLite database.
final class AnagramViewModel: ObservableObject {
    // MARK: - Published properties for SwiftUI
    @Published var query: String = ""
    @Published var results: [String] = []
    @Published var extraLetterResults: [ExtraLetterWord] = []
    
    // MARK: - Private SQLite handle
    private var db: OpaquePointer?

    // MARK: - Initialization
    init() {
        // 1) Locate the bundled .sqlite file
        guard let dbPath = Bundle.main.path(forResource: "scrabble_words", ofType: "sqlite") else {
            fatalError("scrabble_words.sqlite not found in app bundle")
        }
        // 2) Debug: print path and check existence
        print("📂 SQLite path:", dbPath)
        print("🔍 File exists at path?", FileManager.default.fileExists(atPath: dbPath))
        // 3) Open read-only
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            fatalError("Unable to open database at \(dbPath): \(err)")
        }
    }

    // MARK: - Public search method
    /// Normalize input, filter by length + alphagram, then denormalize results.
    func searchAnagrams() {
        results.removeAll()
        
        // 1) Uppercase & normalize digraphs → internal form
        let normalized = normalize(query)
        
        // 2) Compute length and alphagram
        let length = Int32(normalized.count)
        let alphagram = getAnagram(normalized)
        print("🔍 Searching for length=\(length), alphagram='\(alphagram)' ")
        
        // 3) Prepare SQL: filter by length first, then by alphagram
        let sql = "SELECT word FROM words WHERE length = ? AND alphagram = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            print("❌ Prepare failed: \(err)")
            return
        }
        
        // 4) Bind parameters correctly (use transient destructor)
        sqlite3_bind_int(stmt, 1, length)
        sqlite3_bind_text(
            stmt,
            2,
            (alphagram as NSString).utf8String,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
        
        // 5) Execute & collect rows
        var fetched = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            fetched += 1
            if let cStr = sqlite3_column_text(stmt, 0) {
                let internalWord = String(cString: cStr)
                let displayWord = denormalize(internalWord)
                results.append(displayWord)
            }
        }
        print("✅ Fetched \(fetched) rows")
        
        sqlite3_finalize(stmt)
        
        // 6) Search with one extra letter
        var extendedResults = [ExtraLetterWord]()
        let letters = "AÇBCDEFGHIJKLMNOPQRSTUVWXYZNÑ" // Include your internal representation
        for letter in letters {
            let extendedQuery = normalized + String(letter)
            let extendedAlphagram = getAnagram(extendedQuery)
            let extendedLength = Int32(extendedQuery.count)
            
            var extStmt: OpaquePointer?
            let extSQL = "SELECT word FROM words WHERE length = ? AND alphagram = ?;"
            if sqlite3_prepare_v2(db, extSQL, -1, &extStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(extStmt, 1, extendedLength)
                sqlite3_bind_text(
                    extStmt,
                    2,
                    (extendedAlphagram as NSString).utf8String,
                    -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
                while sqlite3_step(extStmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(extStmt, 0) {
                        let internalWord = String(cString: cStr)
                        if !results.contains(internalWord) {
                            let displayWord = denormalize(internalWord)
                            extendedResults.append(ExtraLetterWord(word: displayWord, extraLetter: letter))
                        }
                    }
                }
            }
            sqlite3_finalize(extStmt)
        }
        extraLetterResults = extendedResults.sorted { $0.word < $1.word }
    }

    // MARK: - Cleanup
    deinit {
        sqlite3_close(db)
    }
}
