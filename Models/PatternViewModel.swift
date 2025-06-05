//
//  PatternViewModel.swift
//  ScrabbleFinder
//
//  Created by Isaac Falconer on 2025.05.25.
//

import Foundation
import SQLite3
import TrieKit
import Combine

// MARK: - Pattern match with filled positions
struct PatternSearchResult {
    let word: String
    let filledPositions: [Int]
    let dashRanges: [(start: Int, end: Int)]
}

final class PatternViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var showLongWords: Bool = false        // > 8 letras
    @Published var resultsByLength: [Int: [PatternSearchResult]] = [:]

    private var trie: TrieNode?            // opcional
    private var sqliteDB: OpaquePointer?   // reusar método openSQLite()
    private var cancellables = Set<AnyCancellable>()
    private let anagramModel: AnagramViewModel

    /// Mapa de dígrafos internos a su forma “bonita”
    private let internalToDigraphs: [Character: String] = ["Ç":"CH", "K":"LL", "W":"RR"]

    // Init: recibe AnagramViewModel para compartir trie y sqlite
    init(anagramModel: AnagramViewModel) {
        self.anagramModel = anagramModel
        // Initialize with current trie and sqliteDB
        self.trie = anagramModel.trieRoot
        self.sqliteDB = anagramModel.sqliteDB
        // Subscribe to trieReady to update when loaded
        anagramModel.$trieReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                if ready, let root = anagramModel.trieRoot {
                    self?.updateTrie(root)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Acción principal
    func search() {
        resultsByLength.removeAll()

        guard trie != nil else {
            print("⏳ Trie no listo para búsqueda de patrón.")
            return
        }

        // 1. Parseo
        guard let request = ParsedPattern(query) else { return }

        // 2. Obtener palabras coincidentes usando TRIE con comodines y atril
        print("🧠 Usando TRIE para búsqueda de patrón.")

        // Normalize pattern and rack for trie search
        let normalizedPattern = normalize(request.corePattern) // Use the core pattern before regex conversion
        var normalizedRack = request.rack.map { Array(normalize(String($0))) } ?? []

        let matchedWordsInternal = trie!.searchWithWildcards(pattern: normalizedPattern, patternIndex: 0, rack: &normalizedRack, currentNode: trie!, wildcardsUsed: 0)

        let candidates = matchedWordsInternal.map { denormalize($0) } // Denormalize results

        // 3. Filtrado por rack si existe
        let filtered: [String]
        if let rackChars = request.rack {
            // Internal rack letters
            let normRack = Array(normalize(String(rackChars)))
            // Combine rack + mandatory pattern letters (they're fixed positions)
            // Note: Mandatory letters from the pattern are already handled by the trie search
            let bag = normRack // The rack is already used for filtering during trie search, so just use the normalized rack
            filtered = candidates.filter { fitsRack($0, rack: bag) }
        } else {
            filtered = candidates
        }

        // 4. Longitud fija
        let final = request.length != nil
          ? filtered.filter { $0.count == request.length! }
          : filtered
          
        // 5. Agrupar y ordenar
        for w in final {
            let result = PatternSearchResult(
                word: w,
                filledPositions: request.filledPositions,
                dashRanges: request.dashRanges
            )
            resultsByLength[w.count, default: []].append(result)
        }
        resultsByLength.keys.forEach {
            resultsByLength[$0]?.sort { $0.word < $1.word }
        }
        
        // Debug: log which lengths were found
        let lengths = resultsByLength.keys.sorted()
        print("🔍 Pattern search lengths: \(lengths)")
        
        // Debug: log count per length
        for len in lengths {
            let count = resultsByLength[len]?.count ?? 0
            print("🔍 Length \(len): \(count) words")
        }
    }

    // MARK: - Helpers
    private func fitsRack(_ word: String, rack: [Character]) -> Bool {
        var bag = rack
        for ch in word {
            if let i = bag.firstIndex(of: ch) { bag.remove(at: i) }
            else { return false }
        }
        return true
    }

    private func collectFromTrie(regex: NSRegularExpression) -> [String] {
        guard let trie = trie else { return [] }
        // Use trie’s pattern search extension
        let matches = trie.searchByPattern(regex)
        print("🔍 Trie encontró \(matches.count) palabras para patrón “\(regex.pattern)”")
        return matches
    }

    private func collectFromSQLite(regex: NSRegularExpression) -> [String] {
        guard let db = sqliteDB else { return [] }
        let like = regex.pattern
            .replacingOccurrences(of: ".*", with: "%")
            .replacingOccurrences(of: ".", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "^$"))
        let sql = "SELECT word FROM words WHERE word LIKE ?"
        var stmt: OpaquePointer? = nil
        var words: [String] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, like, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let w = String(cString: cStr)
                    // Normalize digraphs for matching
                    let normalized = normalize(w)
                    if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: normalized.count)) != nil {
                        words.append(w)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return words
    }

    /// Update the trie when the AnagramViewModel finishes loading it
    func updateTrie(_ newTrie: TrieNode) {
        self.trie = newTrie
    }

    /// Convierte la forma interna (Ç/K/W) a dígrafos “bonitos” para la UI.
    func denormalize(_ word: String) -> String {
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
}
// MARK: - Parser -----------------------------------------------------------
private struct ParsedPattern {
    let regex: NSRegularExpression
    let length: Int?          // nil = cualquier longitud
    let rack: [Character]?    // letras del atril (opcional)
    let mandatoryLetters: [Character]
    let filledPositions: [Int]
    let dashRanges: [(start: Int, end: Int)]

    init?(_ raw: String) {
        let parts = raw.uppercased().split(separator: ",", maxSplits: 1).map(String.init)
        // Record which indices came from '*' or '-'
        var filled: [Int] = []
        for (i, ch) in raw.enumerated() {
            if ch == "*" || ch == "-" {
                filled.append(i)
            }
        }
        filledPositions = filled

        // Compute dash ranges in the normalized pattern
        let coreRaw = parts[0]
        let hasLeadingDash = coreRaw.hasPrefix("-")
        let hasTrailingDash = coreRaw.hasSuffix("-")
        var ranges: [(Int, Int)] = []
        if hasLeadingDash && hasTrailingDash {
            ranges = [(0, -1)]
        } else if hasLeadingDash {
            let normalized = normalize(coreRaw)
            let firstFixed = normalized.firstIndex(where: { $0 != "-" && $0 != "*" })?.utf16Offset(in: normalized) ?? normalized.count
            ranges = [(0, firstFixed)]
        } else if hasTrailingDash {
            let normalized = normalize(coreRaw)
            let lastFixed = normalized.lastIndex(where: { $0 != "-" && $0 != "*" })?.utf16Offset(in: normalized) ?? -1
            ranges = [(lastFixed + 1, normalized.count)]
        }
        dashRanges = ranges

        var core = parts[0]
        // Normalize digraphs in the pattern
        core = normalize(core)

        // 2) Capturar letras literales del patrón (gratis en el filtrado)
        let mand = Array(core)
        mandatoryLetters = mand

        // 2) Sustituir wildcard '*' de usuario por '.'
        core = core.replacingOccurrences(of: "*", with: ".")

        rack = parts.count == 2 ? Array(parts[1]) : nil

        // 3) Detectar sufijo :n (longitud fija) ―――――――――――――――――――――
        var fixedLen: Int? = nil
        if let range = core.range(of: #":\d+$"#, options: .regularExpression) {
            let numStr = core[range].dropFirst()        // quita ':'
            fixedLen = Int(numStr)
            core.removeSubrange(range)                  // quita ":n"
        }
        length = fixedLen

        // 4) Traducir guiones '-' ――――――――――――――――――――――――――――――――
        //   -ABC   →  .*ABC$
        //   ABC-   →  ^ABC.*
        //   -ABC-  →  .*ABC.*
        //   (sin guión) → coincidencia exacta
        var patternBody: String
        switch (core.hasPrefix("-"), core.hasSuffix("-")) {
        case (true, true):
            patternBody = ".*" + core.dropFirst().dropLast() + ".*"
        case (true, false):
            patternBody = ".*" + core.dropFirst() + "$"
        case (false, true):
            patternBody = "^" + core.dropLast() + ".*"
        case (false, false):
            patternBody = "^" + core + "$"
        }

        // 5) Compilar regex ――――――――――――――――――――――――――――――――――――
        guard let re = try? NSRegularExpression(pattern: patternBody) else { return nil }
        regex = re
    }
}
