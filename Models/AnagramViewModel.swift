import Foundation
import TrieKit
import SQLite3

// MARK: – Model helpers ------------------------------------------------------

struct ExtraLetterWord: Identifiable {
    let id = UUID()
    let word: String
    let extraLetter: Character
}

/// Resultado con comodines “?”; guarda las letras que sustituyeron cada “?”
struct WildcardWord: Identifiable {
    let id = UUID()
    let word: String
    let wildcardLetters: [Character]   // mismo orden que los “?” del query
}

// MARK: – ViewModel ----------------------------------------------------------

final class AnagramViewModel: ObservableObject {

    // Publicado a la vista
    @Published var query: String = ""
    @Published var results: [String] = []                    // palabras exactas
    @Published var extraLetterResults: [ExtraLetterWord] = []// +1 ficha
    @Published var wildcardResults: [WildcardWord] = []      // con “?”

    @Published var showShorterWordsOnly: Bool = false
    @Published var shorterWordResultsByLength: [Int: [String]] = [:]

    // Trie raíz
    var trieRoot: TrieNode? = nil
    var sqliteDB: OpaquePointer? = nil
    
    @Published var trieReady: Bool = false

    // Conversión de dígrafos ⇆ forma interna
    private let digraphsToInternal: [String: Character] = ["CH":"Ç", "LL":"K", "RR":"W"]
    private let internalToDigraphs: [Character: String] = ["Ç":"CH", "K":"LL", "W":"RR"]

    // Orden especial para los alfagramas
    private let alphaOrder = "AEIOUBCÇDFGHJLKMNÑPQRWSTVXYZ"
    private lazy var orderPos: [Character: Int] =
        Dictionary(uniqueKeysWithValues: alphaOrder.enumerated()
                                                .map { ($0.element, $0.offset) })

    // ------------------------------------------------------------------------
    // Init – carga trie.bin
    // ------------------------------------------------------------------------
    init() {
        // 1) Open SQLite for immediate fallback search
        openSQLite()
        
        // 2) Load trie in background
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = Bundle.main.url(forResource: "trie", withExtension: "bin"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? PropertyListDecoder().decode(TrieNode.self, from: data) else {
                DispatchQueue.main.async {
                    print("❌ Error al cargar trie.bin")
                }
                return
            }
            DispatchQueue.main.async {
                self.trieRoot = decoded
                self.trieReady = true
            }
        }
    }

    // ------------------------------------------------------------------------
    // Búsqueda principal
    // ------------------------------------------------------------------------
    func searchAnagrams() {

        // Limpia salidas previas
        results.removeAll()
        extraLetterResults.removeAll()
        wildcardResults.removeAll()

        // If trie not ready yet, use SQLite fallback
        if trieRoot == nil {
            self.results = fetchFromSQLite(query: query)
            return
        }
        let trie = trieRoot!

        // --------------------------------------------------------------------
        // 1) Procesa texto del usuario → internalBuffer + wildcardCount
        // --------------------------------------------------------------------
        var wildcardCount = 0
        var internalBuffer: [Character] = []

        let upper = Array(query.uppercased())
        var i = 0
        while i < upper.count {
            let ch = upper[i]

            if ch == "?" {                       // comodín
                wildcardCount += 1
                i += 1
                continue
            }

            // Dígrafos CH/LL/RR
            if i + 1 < upper.count {
                let next = upper[i + 1]
                if ch == "C", next == "H" {
                    internalBuffer.append("Ç"); i += 2; continue
                }
                if ch == "L", next == "L" {
                    internalBuffer.append("K"); i += 2; continue
                }
                if ch == "R", next == "R" {
                    internalBuffer.append("W"); i += 2; continue
                }
            }

            if ch.isLetter {                     // Incluye Ñ
                internalBuffer.append(ch)
            }
            i += 1
        }

        let normalized = String(internalBuffer)

        // --------------------------------------------------------------------
        // 2) Sin comodines
        // --------------------------------------------------------------------
        if wildcardCount == 0 {

            // 2-a  exactas
            let alpha      = alphagram(of: normalized)
            let exactRaw   = trie.searchByAlphagram(alpha)
            results        = exactRaw.map { denormalize($0) }

            // 2-b  +1 ficha
            var extras: [ExtraLetterWord] = []
            let letters = "AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ"
            for letter in letters {
                let extAlpha = alphagram(of: normalized + String(letter))
                let matches  = trie.searchByAlphagram(extAlpha)
                for w in matches where !exactRaw.contains(w) {
                    extras.append(ExtraLetterWord(word: denormalize(w),
                                                 extraLetter: letter))
                }
            }
            extraLetterResults = extras.sorted { $0.word < $1.word }
            return
        }

        // --------------------------------------------------------------------
        // 3) Con comodines (hasta 2 “?”)
        // --------------------------------------------------------------------
        let letters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        var seen   = Set<String>()
        var found: [WildcardWord] = []

        func process(_ candidate: String, _ subs: [Character]) {
            let alpha   = alphagram(of: candidate)
            let matches = trie.searchByAlphagram(alpha)
            for w in matches where !seen.contains(w) {
                seen.insert(w)
                found.append(WildcardWord(word: denormalize(w),
                                          wildcardLetters: subs))
            }
        }

        switch wildcardCount {
        case 1:
            for l in letters { process(normalized + String(l), [l]) }
        case 2:
            for l1 in letters {
                for l2 in letters {
                    process(normalized + String(l1) + String(l2), [l1, l2])
                }
            }
        default: break
        }

        wildcardResults = found.sorted { $0.word < $1.word }
    }

    // ------------------------------------------------------------------------
    /// Convierte CH/LL/RR a Ç/K/W, filtra sólo letras y **devuelve mayúsculas internas**.
    private func normalizeInternal(_ word: String) -> String {
        var buffer: [Character] = []
        let upper = Array(word.uppercased())
        var i = 0
        while i < upper.count {
            let ch = upper[i]
            if i + 1 < upper.count {
                let next = upper[i + 1]
                if ch == "C", next == "H" {
                    buffer.append("Ç"); i += 2; continue
                }
                if ch == "L", next == "L" {
                    buffer.append("K"); i += 2; continue
                }
                if ch == "R", next == "R" {
                    buffer.append("W"); i += 2; continue
                }
            }
            if ch.isLetter { buffer.append(ch) }
            i += 1
        }
        return String(buffer)
    }
    // ------------------------------------------------------------------------
    // MARK: – Public validator
    // ------------------------------------------------------------------------
    /// Retorna `true` si la palabra está en el lexicón.
    func isValid(_ word: String) -> Bool {
        let norm = normalizeInternal(word)
        guard !norm.isEmpty else { return false }

        // Si el trie ya está listo, úsalo porque es más rápido
        if let trie = trieRoot {
            let alpha = alphagram(of: norm)
            return trie.searchByAlphagram(alpha).contains(norm)
        }

        // Fallback: consulta en SQLite
        let alpha = alphagram(of: norm)
        return fetchFromSQLiteHasAlpha(alpha)
    }

    /// Devuelve `true` si existe algún registro con ese alfagrama en SQLite.
    private func fetchFromSQLiteHasAlpha(_ alpha: String) -> Bool {
        guard let db = sqliteDB else { return false }
        let sql = "SELECT 1 FROM words WHERE alphagram = ? LIMIT 1"
        var stmt: OpaquePointer? = nil
        var exists = false
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, alpha, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        sqlite3_finalize(stmt)
        return exists
    }

    // ------------------------------------------------------------------------
    // MARK: – Helpers
    // ------------------------------------------------------------------------

    /// Alfagrama con el orden especial
    private func alphagram(of word: String) -> String {
        String(word.sorted { orderPos[$0, default: 999] < orderPos[$1, default: 999] })
    }

    /// Convierte forma interna (Ç/K/W) a dígrafos “bonitos” para la UI.
    private func denormalize(_ word: String) -> String {
        var out = ""
        for ch in word {
            if let digraph = internalToDigraphs[ch] {
                out += digraph
            } else {
                out.append(ch)
            }
        }
        return out
    }

    func generateShorterWords() {
        guard !query.isEmpty else { return }

        shorterWordResultsByLength.removeAll()

        var internalBuffer: [Character] = []

        let upper = Array(query.uppercased())
        var i = 0
        while i < upper.count {
            let ch = upper[i]
            if ch == "?" { i += 1; continue }

            if i + 1 < upper.count {
                let next = upper[i + 1]
                if ch == "C", next == "H" {
                    internalBuffer.append("Ç"); i += 2; continue
                }
                if ch == "L", next == "L" {
                    internalBuffer.append("K"); i += 2; continue
                }
                if ch == "R", next == "R" {
                    internalBuffer.append("W"); i += 2; continue
                }
            }

            if ch.isLetter {
                internalBuffer.append(ch)
            }
            i += 1
        }

        let fullSet = internalBuffer
        let fullLength = fullSet.count

        guard fullLength > 2 else { return }

        var seen = Set<String>()

        for len in stride(from: fullLength - 1, through: 2, by: -1) {
            let combos = combinations(of: fullSet, length: len)
            for c in combos {
                let alpha = alphagram(of: String(c))
                let matches = trieRoot?.searchByAlphagram(alpha) ?? []
                for w in matches where !seen.contains(w) {
                    seen.insert(w)
                    let nice = denormalize(w)
                    shorterWordResultsByLength[len, default: []].append(nice)
                }
            }
        }
    }

    private func combinations(of array: [Character], length: Int) -> Set<[Character]> {
        var results = Set<[Character]>()

        func combine(_ current: [Character], _ remaining: [Character]) {
            if current.count == length {
                results.insert(current.sorted())
                return
            }
            for i in 0..<remaining.count {
                var newCurrent = current
                newCurrent.append(remaining[i])
                var newRemaining = remaining
                newRemaining.remove(at: i)
                combine(newCurrent, newRemaining)
            }
        }

        combine([], array)
        return results
    }
    
    private func openSQLite() {
        guard let path = Bundle.main.path(forResource: "scrabble_words", ofType: "sqlite") else {
            print("⚠️ scrabble_words.sqlite no encontrado en bundle")
            return
        }
        if sqlite3_open(path, &sqliteDB) != SQLITE_OK {
            print("❌ SQLite open error: \(String(cString: sqlite3_errmsg(sqliteDB)))")
        } else {
            print("✅ SQLite database opened at path: \(path)")
            var tableStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(sqliteDB, "SELECT name FROM sqlite_master WHERE type='table';", -1, &tableStmt, nil) == SQLITE_OK {
                while sqlite3_step(tableStmt) == SQLITE_ROW {
                    if let cName = sqlite3_column_text(tableStmt, 0) {
                        print("📋 SQLite table: \(String(cString: cName))")
                    }
                }
                sqlite3_finalize(tableStmt)
            }
        }
    }
    
    private func fetchFromSQLite(query: String) -> [String] {
        guard let db = sqliteDB else { return [] }
        // Normalize input using internal normalization (digraphs, letters, uppercase)
        let normalized = normalizeInternal(query)
        let alpha = alphagram(of: normalized)
        
        print("🔍 SQLite fallback search alpha: \(alpha)")
        
        let sql = "SELECT word FROM words WHERE alphagram = ?"
        var stmt: OpaquePointer? = nil
        var words: [String] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, alpha, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    words.append(String(cString: cString))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        print("🔎 SQLite found \(words.count) words for alpha \(alpha)")
        
        return words
    }
}
