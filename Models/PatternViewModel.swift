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
struct LegacyPatternSearchResult {
    let word: String
    let filledPositions: [Int]
    let dashRanges: [(start: Int, end: Int)]
}

final class PatternViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var showLongWords: Bool = false        // > 8 letras
    @Published var resultsByLength: [Int: [LegacyPatternSearchResult]] = [:]

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

        // 1. Parseo con nueva sintaxis
        guard let request = ParsedPattern(query) else { return }

        // 2. Obtener universo de palabras usando TRIE o SQLite fallback
        let candidates: [String]
        if let _ = trie {
            print("🧠 Usando TRIE para búsqueda de patrón.")
            candidates = collectFromTrie(regex: request.regex)
        } else {
            print("🗃️ Usando SQLite fallback para búsqueda de patrón.")
            candidates = collectFromSQLite(regex: request.regex)
        }
        
        // Debug: count of candidates
        print("🔍 Candidatas totales: \(candidates.count)")

        // 3. Filtrado adicional por letras requeridas/excluidas
        let preFiltered: [String]
        if !request.requiredLetters.isEmpty || !request.excludedLetters.isEmpty || !request.requiredLetterCounts.isEmpty || !request.excludedLetterCounts.isEmpty {
            print("🔍 Running additional filtering for required/excluded letters")
            preFiltered = candidates.filter { word in
                // 🟢 Fix: Required letters now support multiplicity, e.g. +UU requires two Us
                // Verificar cantidad de letras requeridas
                for (reqCh, reqCount) in request.requiredLetterCounts {
                    let countInWord = word.filter { $0 == reqCh }.count
                    if countInWord < reqCount { return false }
                }
                // Verificar letras excluidas (con soporte para multiplicidad)
                for excl in request.excludedLetters {
                    if word.contains(excl) { return false }
                }
                // Verificar cantidad de letras excluidas (multiplicidad)
                for (exclCh, maxCount) in request.excludedLetterCounts {
                    let countInWord = word.filter { $0 == exclCh }.count
                    if countInWord >= maxCount { return false }
                }
                return true
            }
        } else {
            preFiltered = candidates
        }

        // 4. Filtrado por rack si existe (con soporte para comodines)
        let filtered: [String]
        if let rackChars = request.rack {
            let normRack = Array(normalizeText(String(rackChars)))
            let wildcardCount = request.rackWildcardCount
            // Las letras fijas del patrón son gratuitas
            let fixedLetters = request.fixedLetters
            
            print("🔍 Rack filtering: letters=\(normRack), wildcards=\(wildcardCount), fixed=\(fixedLetters)")
            
            // Para cada palabra candidata, verificar si se puede formar con el rack + comodines
            filtered = preFiltered.filter { word in
                var availableRack = normRack
                var wordChars = Array(word)
                var availableWildcards = wildcardCount
                
                // Primero quitar las letras fijas del patrón
                for fixed in fixedLetters {
                    if let idx = wordChars.firstIndex(of: fixed) {
                        wordChars.remove(at: idx)
                    }
                }
                
                // Ahora verificar si las letras restantes están en el rack o se pueden cubrir con comodines
                for ch in wordChars {
                    if let idx = availableRack.firstIndex(of: ch) {
                        // Letra disponible en rack
                        availableRack.remove(at: idx)
                    } else if availableWildcards > 0 {
                        // Usar comodín
                        availableWildcards -= 1
                    } else {
                        // No hay letra en rack ni comodines disponibles
                        return false
                    }
                }
                
                print("🎯 Word '\(word)' matches rack (remaining wildcards: \(availableWildcards))")
                return true
            }
        } else if request.rackWildcardCount > 0 {
            // Solo comodines sin letras específicas en el rack
            let wildcardCount = request.rackWildcardCount
            let fixedLetters = request.fixedLetters
            
            print("🔍 Wildcard-only rack filtering: wildcards=\(wildcardCount), fixed=\(fixedLetters)")
            
            filtered = preFiltered.filter { word in
                var wordChars = Array(word)
                var availableWildcards = wildcardCount
                
                // Primero quitar las letras fijas del patrón
                for fixed in fixedLetters {
                    if let idx = wordChars.firstIndex(of: fixed) {
                        wordChars.remove(at: idx)
                    }
                }
                
                // Verificar si las letras restantes se pueden cubrir con comodines
                let remainingLettersCount = wordChars.count
                if remainingLettersCount <= availableWildcards {
                    print("🎯 Word '\(word)' matches with \(remainingLettersCount) wildcards")
                    return true
                } else {
                    return false
                }
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
            let result = LegacyPatternSearchResult(
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
        
        // For complex patterns with lookaheads, get all words and filter with regex
        // This is less efficient but more accurate than LIKE pattern conversion
        let sql = "SELECT word FROM words"
        var stmt: OpaquePointer? = nil
        var words: [String] = []
        
        print("🔍 SQLite fallback using pattern: \(regex.pattern)")
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
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
        print("🔍 SQLite fallback found \(words.count) matches")
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

// MARK: - Structured Query Components
private struct StructuredQuery {
    let pattern: String
    let poolRestrictions: String
    let lengthRestriction: Int?
}

// MARK: - Parser con Nueva Sintaxis Mejorada
private struct ParsedPattern {
    let regex: NSRegularExpression
    let length: Int?
    let rack: [Character]?
    let rackWildcardCount: Int  // Número de comodines "?" en la restricción de atril (máximo 2)
    let fixedLetters: [Character]  // Letras fijas del patrón (no wildcards)
    let filledPositions: [Int]
    let dashRanges: [(start: Int, end: Int)]
    let requiredLetters: Set<Character>  // Letras que DEBEN estar (+) (legacy set)
    let excludedLetters: Set<Character>  // Letras que NO deben estar (-)
    let requiredLetterCounts: [Character: Int] // Conteo de letras requeridas con multiplicidad
    let excludedLetterCounts: [Character: Int] // Conteo de letras excluidas con multiplicidad
    
    /// Validates and parses structured query syntax: [patrón],[pool]:[longitud]
    private static func parseStructuredQuery(_ input: String) -> StructuredQuery? {
        print("🔍 parseStructuredQuery starting with input: '\(input)'")
        // Expected structure: [patrón],[restricción de pool]:[restricción de longitud]
        // Examples:
        // - "C*,+A-E:5" -> pattern: "C*", pool: "+A-E", length: 5
        // - "P.S,AEI?" -> pattern: "P.S", pool: "AEI?", length: nil
        // - "+ABC-XYZ" -> pattern: "*", pool: "+ABC-XYZ", length: nil (no comma = pool only)
        // - "M*.N:7" -> pattern: "M*.N", pool: "", length: 7 (no comma, has length)
        
        var remaining = input
        var pattern = ""
        var poolRestrictions = ""
        var lengthRestriction: Int? = nil
        
        // 1. Extract length restriction first (rightmost :number)
        if let lengthMatch = remaining.range(of: #":\d+$"#, options: .regularExpression) {
            let lengthStr = String(remaining[lengthMatch]).dropFirst() // Remove ":"
            lengthRestriction = Int(lengthStr)
            remaining.removeSubrange(lengthMatch)
        }
        
        // 2. Check for comma to separate pattern from pool
        if let commaIndex = remaining.firstIndex(of: ",") {
            pattern = String(remaining[..<commaIndex])
            poolRestrictions = String(remaining[remaining.index(after: commaIndex)...])
            
            // Validate: pattern should not contain +/- if comma is present
            if pattern.contains("+") || pattern.contains("-") {
                print("❌ Error: Sintaxis inválida. Estructura esperada: [patrón],[pool]:[longitud]. Las restricciones +/- deben ir después de la coma.")
                return nil
            }
            
            // Validate: length restriction should not be in the middle
            if pattern.contains(":") || poolRestrictions.contains(":") {
                print("❌ Error: Sintaxis inválida. La restricción de longitud (:número) solo puede ir al final.")
                return nil
            }
            
        } else {
            // No comma: determine if it's pattern-only or pool-only
            print("🔍 parseStructuredQuery: no comma, remaining='\(remaining)'")
            if remaining.hasPrefix("+") || remaining.hasPrefix("-") || 
               remaining.contains("2@") || remaining.contains("2&") {
                // Pool restrictions only
                print("🔍 parseStructuredQuery: detected as pool-only")
                pattern = "*"
                poolRestrictions = remaining
            } else {
                // Check for mixed pattern + restrictions without comma (should be invalid)
                let hasPatternChars = remaining.contains { ch in
                    ch.isLetter || ch == "." || ch == "*" || ch == "@" || ch == "&"
                }
                let hasPoolRestrictions = remaining.contains("+") || remaining.contains("-")
                
                if hasPatternChars && hasPoolRestrictions {
                    print("❌ Error: Sintaxis inválida. No se puede mezclar patrón con restricciones sin coma. Use: [patrón],[pool]:[longitud]")
                    return nil
                }
                
                // Pattern only
                pattern = remaining.isEmpty ? "*" : remaining
                poolRestrictions = ""
            }
        }
        
        // 3. Final validation: no stray colons
        if pattern.contains(":") || poolRestrictions.contains(":") {
            print("❌ Error: Sintaxis inválida. La restricción de longitud (:número) solo puede ir al final.")
            return nil
        }
        
        print("🔍 Parsed structure - Pattern: '\(pattern)', Pool: '\(poolRestrictions)', Length: \(lengthRestriction?.description ?? "nil")")
        
        return StructuredQuery(
            pattern: pattern,
            poolRestrictions: poolRestrictions,
            lengthRestriction: lengthRestriction
        )
    }

    init?(_ raw: String) {
        // Strict syntax validation: [patrón],[restricción de pool]:[restricción de longitud]
        let rawUpper = raw.uppercased()
        print("🔍 ParsedPattern initializing with: '\(rawUpper)'")
        
        // Parse the full structure to validate syntax
        guard let parsed = Self.parseStructuredQuery(rawUpper) else {
            print("❌ ParsedPattern: parseStructuredQuery failed for '\(rawUpper)'")
            return nil
        }
        print("🔍 ParsedPattern: parseStructuredQuery succeeded")
        
        // Extract components from parsed structure
        let patternPart = parsed.pattern
        
        // Check if pattern contains "?" wildcards
        if patternPart.contains("?") {
            print("❌ Error: Los comodines solo se admiten en el atril, no en el patrón. Utilice punto para representar cualquier letra individual en el patrón")
            return nil
        }
        
        // Use the parsed structure
        let core = parsed.pattern
        let poolRestrictions = parsed.poolRestrictions
        let lengthFromStructure = parsed.lengthRestriction
        
        // Para filled positions tracking
        var filled: [Int] = []
        for (i, ch) in core.enumerated() {
            if ch == "." || ch == "*" || ch == "@" || ch == "&" {
                filled.append(i)
            }
        }
        filledPositions = filled

        var corePattern = core
        var rackLetters: [Character]? = nil
        
        // --- Begin updated logic: Parse + and - operators recognizing digraphs in parentheses ---
        /// Helper to normalize digraph tokens (CH, LL, RR) to Ç/K/W
        func normalizeToken(_ str: String) -> Character? {
            // Handle multiplicity patterns like "2L", "3R"
            if let regex = try? NSRegularExpression(pattern: "^(\\d+)([A-ZÑÁÉÍÓÚ])$"),
               let match = regex.firstMatch(in: str, range: NSRange(location: 0, length: str.count)) {
                // For multiplicity, we only care about the letter part for normalization
                let letterRange = Range(match.range(at: 2), in: str)!
                let letter = String(str[letterRange])
                return letter.first!
            }
            
            // Handle natural digraphs (without parentheses)
            switch str {
            case "CH": return "Ç"
            case "LL": return "K" 
            case "RR": return "W"
            case let s where s.count == 1: return s.first!
            default: return nil
            }
        }

        // Regex to handle sequences of letters and parenthesized digraphs for + and - operators
        // Updated patterns to handle natural digraphs (CH, LL, RR) and multiplicity (2L, 3R)
        let plusPattern = #"\+([A-ZÑ0-9]+)"#
        let minusPattern = #"-([A-ZÑ0-9]+)"#
        let findTokens = #"(\d+[A-ZÑ]|CH|LL|RR|[A-ZÑ])"#

        var required = Set<Character>()
        var excluded = Set<Character>()
        var requiredCounts: [Character: Int] = [:]
        var excludedCounts: [Character: Int] = [:]
        
        // Pool restrictions for consecutive patterns
        var poolConsecutiveVowels = false
        var poolConsecutiveConsonants = false
        
        // Parse pool restrictions (from right side of comma)
        var poolRestrictionsString = poolRestrictions
        
        print("🔍 Parsing pool restrictions: '\(poolRestrictionsString)'")
        
        // Parse pool consecutive vowels (@@)
        if let match = poolRestrictionsString.range(of: #"@@"#, options: .regularExpression) {
            poolConsecutiveVowels = true
            poolRestrictionsString.removeSubrange(match)
        }
        
        // Parse pool consecutive consonants (&&)
        if let match = poolRestrictionsString.range(of: #"&&"#, options: .regularExpression) {
            poolConsecutiveConsonants = true
            poolRestrictionsString.removeSubrange(match)
        }
        
        // Parse any remaining pool restrictions (rack letters, +/-, etc.) from poolRestrictionsString
        var wildcardCount = 0
        if !poolRestrictionsString.isEmpty {
            // For now, treat remaining as rack if it doesn't start with + or -
            if !poolRestrictionsString.hasPrefix("+") && !poolRestrictionsString.hasPrefix("-") && 
               !poolRestrictionsString.contains("2@") && !poolRestrictionsString.contains("2&") {
                
                // Parse rack letters with multiplicity support (e.g., 3U = UUU)
                var letters: [Character] = []
                let rackString = poolRestrictionsString
                var i = rackString.startIndex
                
                while i < rackString.endIndex {
                    let char = rackString[i]
                    
                    if char == "?" {
                        wildcardCount += 1
                        i = rackString.index(after: i)
                    } else if char.isNumber {
                        // Look for multiplicity pattern like "3U"
                        var numberStr = String(char)
                        var j = rackString.index(after: i)
                        
                        // Collect all consecutive digits
                        while j < rackString.endIndex && rackString[j].isNumber {
                            numberStr.append(rackString[j])
                            j = rackString.index(after: j)
                        }
                        
                        // Check if followed by a letter
                        if j < rackString.endIndex && rackString[j].isLetter {
                            let letter = rackString[j]
                            let count = Int(numberStr) ?? 1
                            // Add multiple instances of the letter
                            for _ in 0..<count {
                                letters.append(letter)
                            }
                            i = rackString.index(after: j) // Skip past the letter
                        } else {
                            // Just a number without letter, treat as regular character
                            if char.isLetter {
                                letters.append(char)
                            }
                            i = rackString.index(after: i)
                        }
                    } else if char.isLetter {
                        letters.append(char)
                        i = rackString.index(after: i)
                    } else {
                        // Skip other characters
                        i = rackString.index(after: i)
                    }
                }
                
                // Validate wildcard count (maximum 2)
                if wildcardCount > 2 {
                    print("❌ Error: máximo 2 comodines permitidos en restricción de atril, encontrados: \(wildcardCount)")
                    return nil
                }
                
                rackLetters = letters.isEmpty ? nil : letters
                print("🔍 Parsed rack with multiplicity: letters=\(letters), wildcards=\(wildcardCount)")
                print("🔍 Original rack string: '\(rackString)'")
            }
        }

        // Parse includes (+) from both core pattern and pool restrictions
        func parseIncludes(_ source: inout String) {
            while let match = source.range(of: plusPattern, options: .regularExpression) {
                let plusGroup = String(source[match]).dropFirst() // remove +
                let tokenRegex = try! NSRegularExpression(pattern: findTokens)
                let plusString = String(plusGroup)
                let nsrange = NSRange(plusString.startIndex..<plusString.endIndex, in: plusString)
                tokenRegex.enumerateMatches(in: plusString, options: [], range: nsrange) { result, _, _ in
                    if let result = result, let range = Range(result.range, in: plusString) {
                        let token = String(plusString[range])
                        
                        // Handle multiplicity patterns like "2L", "3R"
                        if let regex = try? NSRegularExpression(pattern: "^(\\d+)([A-ZÑÁÉÍÓÚ])$"),
                           let match = regex.firstMatch(in: token, range: NSRange(location: 0, length: token.count)) {
                            let countRange = Range(match.range(at: 1), in: token)!
                            let letterRange = Range(match.range(at: 2), in: token)!
                            let count = Int(String(token[countRange])) ?? 1
                            let letter = String(token[letterRange])
                            
                            if let norm = normalizeToken(letter) {
                                required.insert(norm)
                                requiredCounts[norm] = max(requiredCounts[norm, default: 0], count)
                            }
                        }
                        // Handle natural digraphs and single letters
                        else if let norm = normalizeToken(token) {
                            required.insert(norm)
                            requiredCounts[norm, default: 0] += 1
                        }
                    }
                }
                source.removeSubrange(match)
            }
        }
        
        // Parse excludes (-) from both core pattern and pool restrictions
        func parseExcludes(_ source: inout String) {
            while let match = source.range(of: minusPattern, options: .regularExpression) {
                let minusGroup = String(source[match]).dropFirst() // remove -
                let tokenRegex = try! NSRegularExpression(pattern: findTokens)
                let minusString = String(minusGroup)
                let nsrange = NSRange(minusString.startIndex..<minusString.endIndex, in: minusString)
                tokenRegex.enumerateMatches(in: minusString, options: [], range: nsrange) { result, _, _ in
                    if let result = result, let range = Range(result.range, in: minusString) {
                        let token = String(minusString[range])
                        
                        // Handle multiplicity patterns like "2L", "3R" in exclusions
                        if let regex = try? NSRegularExpression(pattern: "^(\\d+)([A-ZÑÁÉÍÓÚ])$"),
                           let match = regex.firstMatch(in: token, range: NSRange(location: 0, length: token.count)) {
                            let countRange = Range(match.range(at: 1), in: token)!
                            let letterRange = Range(match.range(at: 2), in: token)!
                            let count = Int(String(token[countRange])) ?? 1
                            let letter = String(token[letterRange])
                            
                            if let norm = normalizeToken(letter) {
                                excluded.insert(norm)
                                excludedCounts[norm] = max(excludedCounts[norm, default: 0], count)
                            }
                        }
                        // Handle natural digraphs and single letters
                        else if let norm = normalizeToken(token) {
                            excluded.insert(norm)
                        }
                    }
                }
                source.removeSubrange(match)
            }
        }
        
        // Parse from core (positional) - should be empty in new structure
        print("🔍 Core before includes/excludes parsing: '\(corePattern)'")
        parseIncludes(&corePattern)
        parseExcludes(&corePattern)
        print("🔍 Core after includes/excludes parsing: '\(corePattern)'")
        
        // Parse from pool restrictions
        print("🔍 Pool restrictions before parsing: '\(poolRestrictionsString)'")
        parseIncludes(&poolRestrictionsString)
        parseExcludes(&poolRestrictionsString)
        print("🔍 Pool restrictions after parsing: '\(poolRestrictionsString)'")
        print("🔍 Required letters: \(required)")
        print("🔍 Required counts: \(requiredCounts)")
        print("🔍 Excluded letters: \(excluded)")
        print("🔍 Excluded counts: \(excludedCounts)")
        // --- End updated logic ---
        
        requiredLetters = required
        excludedLetters = excluded
        requiredLetterCounts = requiredCounts
        excludedLetterCounts = excludedCounts
        rack = rackLetters
        rackWildcardCount = wildcardCount
        
        // Use length from structured parsing
        length = lengthFromStructure
        
        // --- Begin added logic for empty core pattern ---
        // If after removing + and - operators and length suffix the core pattern is empty,
        // it means the user only provided required/excluded letters.
        // To match all words (filtered later by required/excluded letters),
        // replace corePattern with "*" to match any sequence.
        if corePattern.isEmpty {
            corePattern = "*"
        }
        // --- End added logic ---
        
        // --- Begin added logic for simplified patterns like X*Y:n ---
        // Check if the corePattern matches a simplified pattern: single letter, a single *, single letter
        // and length is specified. If so, replace * with the correct number of '.' to match length.
        // Example: P*S:5 -> P...S (3 dots because length=5, 2 letters fixed + 3 wildcards = 5)
        if let length = lengthFromStructure {
            let starCount = corePattern.filter { $0 == "*" }.count
            // Match pattern like: single letter + '*' + single letter (exactly 3 characters)
            if starCount == 1 &&
                corePattern.count == 3,
                corePattern.first?.isLetter == true,
                corePattern.last?.isLetter == true {
                // Calculate number of dots needed to fill length
                let dotsCount = length - 2
                if dotsCount >= 0 {
                    let startChar = corePattern.first!
                    let endChar = corePattern.last!
                    // Build new core pattern with dotsCount dots
                    corePattern = String(startChar) + String(repeating: ".", count: dotsCount) + String(endChar)
                }
            }
        }
        // --- End added logic ---
        
        // 3) Normalizar el patrón y extraer letras fijas
        let normalizedPattern = Self.normalizePattern(corePattern)
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
                .replacingOccurrences(of: "*", with: "[A-ZÑÇKW]*")  // * significa cero o más letras cualesquiera
                .replacingOccurrences(of: "@@", with: "[AEIOU]{2}")  // @@ = dos vocales consecutivas
                .replacingOccurrences(of: "&&", with: "[BCDFGHJKLMNÑPQRSTVWXYZÇKW]{2}")  // && = dos consonantes consecutivas
                .replacingOccurrences(of: "@", with: "[AEIOU]")     // @ = cualquier vocal (después de @@)
                .replacingOccurrences(of: "&", with: "[BCDFGHJKLMNÑPQRSTVWXYZÇKW]")  // & = cualquier consonante (después de &&)
            
            // Asegurar que el patrón sea completo (^ y $)
            if !tempPattern.hasPrefix("^") {
                tempPattern = "^" + tempPattern
            }
            if !tempPattern.hasSuffix("$") {
                tempPattern = tempPattern + "$"
            }
            
            regexPattern = tempPattern
        }
        
        // 5) Agregar lookaheads para letras requeridas y excluidas
        var finalPattern = "^"
        
        // Lookaheads positivos para letras requeridas (simple presence check)
        // Multiplicity will be handled by filtering logic in search()
        for letter in required {
            finalPattern += "(?=.*\(letter))"
        }
        
        // Lookahead negativo para letras excluidas
        if !excluded.isEmpty {
            let excludedSet = excluded.map(String.init).joined()
            finalPattern += "(?!.*[\(excludedSet)])"
        }
        
        // Lookaheads para restricciones de pool consecutivas
        if poolConsecutiveVowels {
            finalPattern += "(?=.*[AEIOU]{2})"
        }
        
        if poolConsecutiveConsonants {
            finalPattern += "(?=.*[BCDFGHJKLMNÑPQRSTVWXYZÇKW]{2})"
        }
        
        // Agregar el patrón principal
        finalPattern += regexPattern
        // Si regexPattern ya tiene ^ al inicio, removerlo, pues ya agregamos finalPattern="^"
        if finalPattern.hasPrefix("^^") {
            finalPattern.remove(at: finalPattern.startIndex)
        }
        
        // Compilar regex
        print("🔍 Input query: \(raw)")
        print("🔍 Parsed core pattern: \(core)")
        print("🔍 Pool restrictions: \(poolRestrictions)")
        print("🔍 Normalized pattern: \(normalizedPattern)")
        print("🔍 Generated regex pattern: \(finalPattern)")
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
            
            // Manejar elipsis Unicode "…" y diéresis "¨" convirtiéndolos a tres puntos exactos
            if ch == "…" || ch == "¨" {
                result.append("...")  // Tres posiciones exactas
                i += 1
                continue
            }
            
            // Los comodines "?" no están permitidos en el patrón
            if ch == "?" {
                print("❌ Error en normalizePattern: Los comodines '?' no están permitidos en el patrón")
                // No procesar el carácter, simplemente continuar
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
            
            // Letra normal o símbolos especiales
            if ch.isLetter || ch == "@" || ch == "&" {
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

