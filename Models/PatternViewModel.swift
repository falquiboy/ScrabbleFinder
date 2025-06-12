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

    /// Mapa de dígrafos internos a su forma "bonita"
    private let internalToDigraphs: [Character: String] = ["Ç":"CH", "K":"LL", "W":"RR"]
    private let digraphsToInternal: [String: Character] = ["CH":"Ç", "LL":"K", "RR":"W"]

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

        // 1. Parseo con nueva sintaxis
        guard let request = ParsedPattern(query) else { return }

        // 2. Obtener universo de palabras usando TRIE
        print("🧠 Usando TRIE para búsqueda de patrón.")
        let candidates = collectFromTrie(regex: request.regex)
        
        // Debug: count of candidates
        print("🔍 Candidatas totales: \(candidates.count)")

        // 3. Filtrado adicional por letras requeridas/excluidas
        let preFiltered: [String]
        if !request.requiredLetters.isEmpty || !request.excludedLetters.isEmpty {
            preFiltered = candidates.filter { word in
                // 🟢 Fix: Required letters now support multiplicity, e.g. +UU requires two Us
                // Verificar cantidad de letras requeridas
                for (reqCh, reqCount) in request.requiredLetterCounts {
                    let countInWord = word.filter { $0 == reqCh }.count
                    if countInWord < reqCount { return false }
                }
                // Verificar letras excluidas
                for excl in request.excludedLetters {
                    if word.contains(excl) { return false }
                }
                return true
            }
        } else {
            preFiltered = candidates
        }

        // 4. Filtrado por rack si existe
        let filtered: [String]
        if let rackChars = request.rack {
            let normRack = Array(normalizeText(String(rackChars)))
            // Las letras fijas del patrón son gratuitas
            let fixedLetters = request.fixedLetters
            
            // Para cada palabra candidata, verificar si se puede formar con el rack
            filtered = preFiltered.filter { word in
                var availableRack = normRack
                var wordChars = Array(word)
                
                // Primero quitar las letras fijas del patrón
                for fixed in fixedLetters {
                    if let idx = wordChars.firstIndex(of: fixed) {
                        wordChars.remove(at: idx)
                    }
                }
                
                // Ahora verificar si las letras restantes están en el rack
                for ch in wordChars {
                    if let idx = availableRack.firstIndex(of: ch) {
                        availableRack.remove(at: idx)
                    } else {
                        return false
                    }
                }
                return true
            }
        } else {
            filtered = preFiltered
        }

        // 5. Longitud fija
        let final = request.length != nil
          ? filtered.filter { $0.count == request.length! }
          : filtered

        // Debug
        print("🔍 Finales: \(final.count) palabras")

        // 6. Agrupar y ordenar
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
        
        // Log resultados
        let totalResults = resultsByLength.values.reduce(0) { $0 + $1.count }
        print("🔍 Búsqueda de patrón encontró \(totalResults) palabras")
    }

    // MARK: - Helpers
    private func collectFromTrie(regex: NSRegularExpression) -> [String] {
        guard let trie = trie else { return [] }
        // Use trie's pattern search extension
        let matches = trie.searchByPattern(regex)
        print("🔍 Trie encontró \(matches.count) palabras para patrón: \(regex.pattern)")
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
                    let normalized = normalizeText(w)
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

    /// Convierte la forma interna (Ç/K/W) a dígrafos "bonitos" para la UI.
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
    
    /// Convierte CH/LL/RR a Ç/K/W y devuelve mayúsculas
    private func normalizeText(_ text: String) -> String {
        var buffer: [Character] = []
        let upper = Array(text.uppercased())
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
}

// MARK: - Parser con Nueva Sintaxis Mejorada
private struct ParsedPattern {
    let regex: NSRegularExpression
    let length: Int?
    let rack: [Character]?
    let fixedLetters: [Character]  // Letras fijas del patrón (no wildcards)
    let filledPositions: [Int]
    let dashRanges: [(start: Int, end: Int)]
    let requiredLetters: Set<Character>  // Letras que DEBEN estar (+) (legacy set)
    let excludedLetters: Set<Character>  // Letras que NO deben estar (-)
    let requiredLetterCounts: [Character: Int] // Conteo de letras requeridas con multiplicidad

    init?(_ raw: String) {
        let parts = raw.uppercased().split(separator: ",", maxSplits: 1).map(String.init)
        
        // Para filled positions tracking
        var filled: [Int] = []
        let patternOnly = parts[0]
        for (i, ch) in patternOnly.enumerated() {
            if ch == "." || ch == "*" {
                filled.append(i)
            }
        }
        filledPositions = filled

        var core = parts[0]
        rack = parts.count == 2 ? Array(parts[1]) : nil
        
        // --- Begin updated logic: Parse + and - operators recognizing digraphs in parentheses ---
        /// Helper to normalize digraph tokens (CH, LL, RR) to Ç/K/W
        func normalizeToken(_ str: String) -> Character? {
            switch str {
            case "CH": return "Ç"
            case "LL": return "K"
            case "RR": return "W"
            case let s where s.count == 1: return s.first!
            default: return nil
            }
        }

        // Regex to handle sequences of letters and parenthesized digraphs for + and - operators
        let plusPattern = #"\+((?:[A-ZÑ]+|\([A-Z]{2}\))+)"#
        let minusPattern = #"-((?:[A-ZÑ]+|\([A-Z]{2}\))+)"#
        let findTokens = #"([A-ZÑ]{1}|\([A-Z]{2}\))"#

        var required = Set<Character>()
        var excluded = Set<Character>()
        var requiredCounts: [Character: Int] = [:]

        // Parse includes (+), extracting letters and parenthesized digraphs as units
        while let match = core.range(of: plusPattern, options: .regularExpression) {
            let plusGroup = String(core[match]).dropFirst() // remove +
            let tokenRegex = try! NSRegularExpression(pattern: findTokens)
            let plusString = String(plusGroup)
            let nsrange = NSRange(plusString.startIndex..<plusString.endIndex, in: plusString)
            tokenRegex.enumerateMatches(in: plusString, options: [], range: nsrange) { result, _, _ in
                if let result = result, let range = Range(result.range, in: plusString) {
                    var token = String(plusString[range])
                    if token.hasPrefix("(") && token.hasSuffix(")") {
                        token = String(token.dropFirst().dropLast()) // Remove ()
                    }
                    if let norm = normalizeToken(token) {
                        required.insert(norm)
                        requiredCounts[norm, default: 0] += 1
                    }
                }
            }
            core.removeSubrange(match)
        }

        // Parse excludes (-), extracting letters and parenthesized digraphs as units
        while let match = core.range(of: minusPattern, options: .regularExpression) {
            let minusGroup = String(core[match]).dropFirst() // remove -
            let tokenRegex = try! NSRegularExpression(pattern: findTokens)
            let minusString = String(minusGroup)
            let nsrange = NSRange(minusString.startIndex..<minusString.endIndex, in: minusString)
            tokenRegex.enumerateMatches(in: minusString, options: [], range: nsrange) { result, _, _ in
                if let result = result, let range = Range(result.range, in: minusString) {
                    var token = String(minusString[range])
                    if token.hasPrefix("(") && token.hasSuffix(")") {
                        token = String(token.dropFirst().dropLast()) // Remove ()
                    }
                    if let norm = normalizeToken(token) {
                        excluded.insert(norm)
                    }
                }
            }
            core.removeSubrange(match)
        }
        // --- End updated logic ---
        
        requiredLetters = required
        excludedLetters = excluded
        requiredLetterCounts = requiredCounts
        
        // 2) Detectar sufijo :n (longitud fija)
        var fixedLen: Int? = nil
        if let range = core.range(of: #":\d+$"#, options: .regularExpression) {
            let numStr = core[range].dropFirst()
            fixedLen = Int(numStr)
            core.removeSubrange(range)
        }
        length = fixedLen
        
        // --- Begin added logic for empty core pattern ---
        // If after removing + and - operators and length suffix the core pattern is empty,
        // it means the user only provided required/excluded letters.
        // To match all words (filtered later by required/excluded letters),
        // replace core with "*" to match any sequence.
        if core.isEmpty {
            core = "*"
        }
        // --- End added logic ---
        
        // --- Begin added logic for simplified patterns like X*Y:n ---
        // Check if the core matches a simplified pattern: single letter, a single *, single letter
        // and length is specified. If so, replace * with the correct number of '.' to match length.
        // Example: P*S:5 -> P...S (3 dots because length=5, 2 letters fixed + 3 wildcards = 5)
        if let length = fixedLen {
            let starCount = core.filter { $0 == "*" }.count
            // Match pattern like: single letter + '*' + single letter (exactly 3 characters)
            if starCount == 1 &&
                core.count == 3,
                core.first?.isLetter == true,
                core.last?.isLetter == true {
                // Calculate number of dots needed to fill length
                let dotsCount = length - 2
                if dotsCount >= 0 {
                    let startChar = core.first!
                    let endChar = core.last!
                    // Build new core pattern with dotsCount dots
                    core = String(startChar) + String(repeating: ".", count: dotsCount) + String(endChar)
                }
            }
        }
        // --- End added logic ---
        
        // 3) Normalizar el patrón y extraer letras fijas
        let normalizedPattern = Self.normalizePattern(core)
        var fixedChars: [Character] = []
        
        // Extraer letras fijas (todo lo que no sea . o *)
        var i = 0
        while i < normalizedPattern.count {
            let ch = normalizedPattern[normalizedPattern.index(normalizedPattern.startIndex, offsetBy: i)]
            if ch != "." && ch != "*" {
                fixedChars.append(ch)
            }
            i += 1
        }
        fixedLetters = fixedChars
        
        // 4) Construir el patrón regex

        // 🟢 Fix: Always match all valid letters when only constraints are present
        let regexPattern: String
        if normalizedPattern == "*" {
            // If pattern is just *, match one or more letters (allowed charset)
            regexPattern = "[A-ZÑÇKW]+"
        } else {
            // Otherwise, build pattern from normalizedPattern as before
            var tempPattern = normalizedPattern
                .replacingOccurrences(of: ".", with: "[A-ZÑÇKW]")  // cualquier letra incluyendo dígrafos internos
            
            // Asegurar que el patrón sea completo (^ y $)
            if !tempPattern.hasPrefix("^") {
                tempPattern = "^" + tempPattern
            }
            if !tempPattern.hasSuffix("$") && !tempPattern.hasSuffix("*") {
                tempPattern = tempPattern + "$"
            }
            
            // Si termina con *, agregar $ después
            if tempPattern.hasSuffix("*") {
                tempPattern = tempPattern + "$"
            }
            regexPattern = tempPattern
        }
        
        // 5) Agregar lookaheads para letras requeridas y excluidas
        var finalPattern = "^"
        
        // Lookaheads positivos para letras requeridas
        for letter in required {
            finalPattern += "(?=.*\(letter))"
        }
        
        // Lookahead negativo para letras excluidas
        if !excluded.isEmpty {
            let excludedSet = excluded.map(String.init).joined()
            finalPattern += "(?!.*[\(excludedSet)])"
        }
        
        // Agregar el patrón principal
        finalPattern += regexPattern
        // Si regexPattern ya tiene ^ al inicio, removerlo, pues ya agregamos finalPattern="^"
        if finalPattern.hasPrefix("^^") {
            finalPattern.remove(at: finalPattern.startIndex)
        }
        
        // Compilar regex
        guard let re = try? NSRegularExpression(pattern: finalPattern) else {
            print("❌ Error compilando regex: \(finalPattern)")
            return nil
        }
        regex = re
        
        // Compute dash ranges (para compatibilidad, aunque ya no usamos -)
        dashRanges = []
    }
    
    /// Normaliza el patrón convirtiendo dígrafos y manejando wildcards
    private static func normalizePattern(_ pattern: String) -> String {
        var result = ""
        let upper = Array(pattern.uppercased())
        var i = 0
        
        while i < upper.count {
            let ch = upper[i]
            
            // Manejar wildcards especiales
            if ch == "." || ch == "*" {
                result.append(ch)
                i += 1
                continue
            }
            
            // Manejar ? como comodín en el patrón (se procesa como .)
            if ch == "?" {
                result.append(".")
                i += 1
                continue
            }
            
            // Verificar dígrafos
            if i + 1 < upper.count {
                let next = upper[i + 1]
                if ch == "C", next == "H" {
                    result.append("Ç")
                    i += 2
                    continue
                }
                if ch == "L", next == "L" {
                    result.append("K")
                    i += 2
                    continue
                }
                if ch == "R", next == "R" {
                    result.append("W")
                    i += 2
                    continue
                }
            }
            
            // Letra normal
            if ch.isLetter {
                result.append(ch)
            }
            i += 1
        }
        
        return result
    }
    
    /// Normaliza texto general (para + y -)
    private static func normalizeForPattern(_ text: String) -> String {
        var buffer: [Character] = []
        let upper = Array(text.uppercased())
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
}

