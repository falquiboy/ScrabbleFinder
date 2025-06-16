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
    
    // MARK: - Validation Functions
    
    /// Validates if string contains only valid Spanish Scrabble characters
    static func isValidSpanishInput(_ input: String) -> Bool {
        let normalized = normalize(input)
        let validChars = Set(alphabetOrder)
        return normalized.allSatisfy { validChars.contains($0) }
    }
}