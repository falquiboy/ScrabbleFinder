import Foundation

// MARK: - Spanish Scrabble Utilities
// Centralized functions for Spanish digraph handling and alphabetical ordering

struct SpanishUtils {
    
    // MARK: - Digraph Mappings
    private static let digraphsToInternal: [String: Character] = [
        "CH": "Ç",
        "LL": "K", 
        "RR": "W"
    ]
    
    private static let internalToDigraphs: [Character: String] = [
        "Ç": "CH",
        "K": "LL",
        "W": "RR"
    ]
    
    // MARK: - Spanish Alphabet Order
    private static let spanishAlphabet: [String] = [
        "A", "E", "I", "O", "U", "B", "C", "CH", "D", "F", "G", "H", "J", "L", "LL",
        "M", "N", "Ñ", "P", "Q", "R", "RR", "S", "T", "V", "X", "Y", "Z"
    ]
    
    private static let alphabetOrder: [Character] = Array("AEIOUBCÇDFGHJLKMNÑPQRWSTVXYZ")
    
    private static let orderMap: [Character: Int] = {
        var map = [Character: Int]()
        for (index, char) in alphabetOrder.enumerated() {
            map[char] = index
        }
        return map
    }()
    
    private static let spanishOrderMap: [String: Int] = {
        var map = [String: Int]()
        for (index, letter) in spanishAlphabet.enumerated() {
            map[letter] = index
        }
        return map
    }()
    
    // MARK: - Normalization Functions
    
    /// Converts user input to internal representation (CH→Ç, LL→K, RR→W)
    static func normalize(_ input: String) -> String {
        var output = input.uppercased()
        for (digraph, replacement) in digraphsToInternal {
            output = output.replacingOccurrences(of: digraph, with: String(replacement))
        }
        return output
    }
    
    /// Converts internal representation back to display format (Ç→CH, K→LL, W→RR)
    static func denormalize(_ input: String) -> String {
        var output = input
        for (internalChar, digraph) in internalToDigraphs {
            output = output.replacingOccurrences(of: String(internalChar), with: digraph)
        }
        return output
    }
    
    // MARK: - Sorting Functions
    
    /// Generates alphagram using Spanish alphabetical order for anagram searches
    static func generateAlphagram(_ input: String) -> String {
        let chars = Array(input)
        let sorted = chars.sorted { a, b in
            let orderA = orderMap[a] ?? Int.max
            let orderB = orderMap[b] ?? Int.max
            return orderA < orderB
        }
        return String(sorted)
    }
    
    /// Splits word into Spanish alphabet units (handling digraphs)
    static func splitIntoSpanishUnits(_ word: String) -> [String] {
        var result: [String] = []
        let upper = word.uppercased()
        var i = upper.startIndex
        
        while i < upper.endIndex {
            let next = upper.index(after: i)
            if next < upper.endIndex {
                let pair = String(upper[i...upper.index(after: i)])
                if spanishOrderMap.keys.contains(pair) {
                    result.append(pair)
                    i = upper.index(i, offsetBy: 2)
                    continue
                }
            }
            result.append(String(upper[i]))
            i = upper.index(after: i)
        }
        return result
    }
    
    /// Spanish alphabetical comparison for sorting results
    static func compareSpanishOrder(_ a: String, _ b: String) -> Bool {
        let unitsA = splitIntoSpanishUnits(a)
        let unitsB = splitIntoSpanishUnits(b)
        let count = min(unitsA.count, unitsB.count)
        
        for i in 0..<count {
            let unitA = unitsA[i]
            let unitB = unitsB[i]
            let orderA = spanishOrderMap[unitA] ?? Int.max
            let orderB = spanishOrderMap[unitB] ?? Int.max
            
            if orderA != orderB {
                return orderA < orderB
            }
        }
        return unitsA.count < unitsB.count
    }
    
    // MARK: - Letter Values (Spanish Scrabble)
    
    private static let letterValues: [Character: Int] = [
        // 1 punto: A ×12, E ×12, I ×6, L ×4, N ×5, O ×9, R ×5, S ×6, T ×4, U ×5
        "A": 1, "E": 1, "I": 1, "L": 1, "N": 1, "O": 1, "R": 1, "S": 1, "T": 1, "U": 1,
        // 2 puntos: D ×5, G ×2
        "D": 2, "G": 2,
        // 3 puntos: B ×2, C ×4, M ×2, P ×2
        "B": 3, "C": 3, "M": 3, "P": 3,
        // 4 puntos: F ×1, H ×2, V ×1, Y ×1
        "F": 4, "H": 4, "V": 4, "Y": 4,
        // 5 puntos: Ch ×1, Q ×1
        "Ç": 5, "Q": 5,  // CH (Ç) y Q
        // 8 puntos: J ×1, LL ×1, Ñ ×1, RR ×1, X ×1
        "J": 8, "K": 8, "Ñ": 8, "W": 8, "X": 8,  // LL(K) y RR(W) internamente
        // 10 puntos: Z ×1
        "Z": 10
        // Nota: 2 comodines (0 puntos) - manejados separadamente
    ]
    
    /// Gets the Scrabble point value for a letter (Spanish rules)
    static func getLetterValue(_ letter: Character) -> Int {
        return letterValues[letter.uppercased().first ?? letter] ?? 0
    }
    
    /// Checks if a letter has medium/high value (≥3 points)
    static func isMediumOrHighValue(_ letter: Character) -> Bool {
        return getLetterValue(letter) >= 3
    }
    
    /// Checks if a word is "relevant" for wildcard results
    /// Requirements: Contains letters from rack AND has medium/high value letters within ±3 positions of other rack letters
    /// IMPORTANT: Wildcard positions count for distance calculation but wildcards themselves don't count as medium/high value letters
    /// IMPORTANT: Uses Spanish letter positioning where digraphs (CH, LL, RR) count as single positions
    static func isRelevantWildcardWord(_ word: String, rackLetters: [Character], wildcardPositions: [Int] = []) -> Bool {
        // Convert wildcard positions from character-based to Spanish unit-based positions
        let normalizedWord = normalize(word)
        let wordUnits = splitIntoSpanishUnits(denormalize(normalizedWord)) // Convert back to display format for proper unit splitting
        let normalizedRack = rackLetters.map { normalize(String($0)).first ?? $0 }
        
        print("🎯 Analyzing '\(word)' for relevance:")
        print("  - Rack letters: \(rackLetters)")
        print("  - Wildcard positions (char-based): \(wildcardPositions)")
        print("  - Word units: \(wordUnits)")
        
        // Convert character-based wildcard positions to Spanish unit-based positions
        var unitBasedWildcardPositions = Set<Int>()
        for charPos in wildcardPositions {
            // Find which Spanish unit this character position corresponds to
            var charIndex = 0
            for (unitIndex, unit) in wordUnits.enumerated() {
                let unitLength = normalize(unit).count
                if charPos >= charIndex && charPos < charIndex + unitLength {
                    unitBasedWildcardPositions.insert(unitIndex)
                    break
                }
                charIndex += unitLength
            }
        }
        
        print("  - Wildcard positions (unit-based): \(unitBasedWildcardPositions)")
        
        // Find positions of rack letters in the word (including wildcard positions for distance calculation)
        var allRackPositions: [Int] = [] // All positions (rack letters + wildcards)
        var mediumHighPositions: [Int] = [] // Only medium/high value rack letters (excluding wildcards)
        
        for (unitIndex, unit) in wordUnits.enumerated() {
            let normalizedUnit = normalize(unit)
            let unitChar = normalizedUnit.first ?? Character(" ")
            
            if unitBasedWildcardPositions.contains(unitIndex) {
                // Wildcard position: counts for distance but not as medium/high value
                allRackPositions.append(unitIndex)
                print("  - Position \(unitIndex): '\(unit)' = WILDCARD")
            } else if normalizedRack.contains(unitChar) {
                // Rack letter position: counts for both distance and medium/high value check
                allRackPositions.append(unitIndex)
                let isHighValue = isMediumOrHighValue(unitChar)
                if isHighValue {
                    mediumHighPositions.append(unitIndex)
                }
                print("  - Position \(unitIndex): '\(unit)' = RACK (\(getLetterValue(unitChar)) pts, high: \(isHighValue))")
            }
        }
        
        print("  - All rack positions: \(allRackPositions)")
        print("  - Medium/high positions: \(mediumHighPositions)")
        
        // Must have at least one medium/high value letter from rack (not including wildcards)
        guard !mediumHighPositions.isEmpty else { 
            print("  - ❌ No medium/high value letters from rack")
            return false 
        }
        
        // Check if any medium/high value letter is at least 3 positions away from other positions
        // This ensures the valuable letter can potentially combine with word bonuses
        for mediumPos in mediumHighPositions {
            for otherPos in allRackPositions {
                let distance = abs(mediumPos - otherPos)
                if otherPos != mediumPos && distance >= 3 {
                    print("  - ✅ RELEVANT: Position \(mediumPos) at least 3 away from position \(otherPos) (distance: \(distance))")
                    return true
                }
            }
        }
        
        print("  - ❌ No medium/high value letters at least 3 positions away from other positions")
        return false
    }
    
    // MARK: - Validation Functions
    
    /// Validates if string contains only valid Spanish Scrabble characters
    static func isValidSpanishInput(_ input: String) -> Bool {
        let normalized = normalize(input)
        let validChars = Set(alphabetOrder)
        return normalized.allSatisfy { validChars.contains($0) }
    }
}