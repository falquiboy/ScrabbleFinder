import Foundation

// MARK: - Pattern Data Structures

/// Represents a parsed pattern search query
struct PatternQuery {
    let pattern: PatternStructure
    let restrictions: PatternRestrictions
    let originalInput: String
}

/// Represents the structural pattern part (before comma)
struct PatternStructure {
    let elements: [PatternElement]
    let rawPattern: String
    
    var isEmpty: Bool {
        return elements.isEmpty
    }
}

/// Individual elements that make up a pattern
enum PatternElement {
    case literal(String)           // Actual letters: "CASA"
    case anyLetter                 // . (one letter)
    case anyLetters                // * (zero or more letters)
    case vocal                     // @ (one vowel)
    case vocalsAdjacent(Int)      // @@ or 2@ (vowels together vs anywhere)
    case consonant                 // & (one consonant)
    case consonantsAdjacent(Int)  // && or 2& (consonants together vs anywhere)
}

/// Represents all restrictions (after comma)
struct PatternRestrictions {
    let includes: [String: Int]    // +ABC -> ["A": 1, "B": 1, "C": 1]
    let excludes: Set<String>      // -ABC -> ["A", "B", "C"]
    let exclusiveRack: [String]    // AEEBRS -> ["A", "E", "E", "B", "R", "S"]
    let wildcardCount: Int         // Number of ? in exclusive rack
    let length: Int?               // :5 -> 5
    
    var hasExclusiveRack: Bool {
        return !exclusiveRack.isEmpty
    }
    
    var hasInclusions: Bool {
        return !includes.isEmpty
    }
    
    var hasExclusions: Bool {
        return !excludes.isEmpty
    }
    
    var hasLengthRestriction: Bool {
        return length != nil
    }
}

// MARK: - Pattern Parser

/// Parses user input into structured pattern queries
class PatternParser {
    
    // MARK: - Public Interface
    
    /// Main parsing function
    static func parse(_ input: String) -> Result<PatternQuery, PatternParseError> {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return .failure(.emptyInput)
        }
        
        // Split by comma
        let components = trimmedInput.components(separatedBy: ",")
        let patternPart = components[0].uppercased()
        let restrictionsPart = components.count > 1 ? components[1] : ""
        
        do {
            let pattern = try parsePattern(patternPart)
            let restrictions = try parseRestrictions(restrictionsPart)
            
            let query = PatternQuery(
                pattern: pattern,
                restrictions: restrictions,
                originalInput: trimmedInput
            )
            
            return .success(query)
        } catch let error as PatternParseError {
            return .failure(error)
        } catch {
            return .failure(.unknownError(error.localizedDescription))
        }
    }
    
    // MARK: - Pattern Parsing
    
    private static func parsePattern(_ input: String) -> PatternStructure {
        var elements: [PatternElement] = []
        var i = input.startIndex
        
        while i < input.endIndex {
            let char = input[i]
            
            switch char {
            case ".":
                elements.append(.anyLetter)
                i = input.index(after: i)
                
            case "*":
                elements.append(.anyLetters)
                i = input.index(after: i)
                
            case "@":
                let (element, nextIndex) = parseVocalPattern(input, startingAt: i)
                elements.append(element)
                i = nextIndex
                
            case "&":
                let (element, nextIndex) = parseConsonantPattern(input, startingAt: i)
                elements.append(element)
                i = nextIndex
                
            case "0"..."9":
                let (element, nextIndex) = parseNumberedPattern(input, startingAt: i)
                if let element = element {
                    elements.append(element)
                }
                i = nextIndex
                
            default:
                // Literal character or sequence
                let (literalString, nextIndex) = parseLiteralSequence(input, startingAt: i)
                elements.append(.literal(literalString))
                i = nextIndex
            }
        }
        
        return PatternStructure(elements: elements, rawPattern: input)
    }
    
    private static func parseVocalPattern(_ input: String, startingAt index: String.Index) -> (PatternElement, String.Index) {
        var nextIndex = input.index(after: index)
        var count = 1
        
        // Count consecutive @ symbols
        while nextIndex < input.endIndex && input[nextIndex] == "@" {
            count += 1
            nextIndex = input.index(after: nextIndex)
        }
        
        return (.vocalsAdjacent(count), nextIndex)
    }
    
    private static func parseConsonantPattern(_ input: String, startingAt index: String.Index) -> (PatternElement, String.Index) {
        var nextIndex = input.index(after: index)
        var count = 1
        
        // Count consecutive & symbols
        while nextIndex < input.endIndex && input[nextIndex] == "&" {
            count += 1
            nextIndex = input.index(after: nextIndex)
        }
        
        return (.consonantsAdjacent(count), nextIndex)
    }
    
    private static func parseNumberedPattern(_ input: String, startingAt index: String.Index) -> (PatternElement?, String.Index) {
        var nextIndex = index
        var numberString = ""
        
        // Extract number
        while nextIndex < input.endIndex && input[nextIndex].isNumber {
            numberString.append(input[nextIndex])
            nextIndex = input.index(after: nextIndex)
        }
        
        guard let number = Int(numberString), nextIndex < input.endIndex else {
            return (nil, nextIndex)
        }
        
        let symbol = input[nextIndex]
        nextIndex = input.index(after: nextIndex)
        
        switch symbol {
        case "@":
            return (.vocalsAdjacent(number), nextIndex)
        case "&":
            return (.consonantsAdjacent(number), nextIndex)
        default:
            // Not a pattern, treat as literal
            return (.literal(numberString + String(symbol)), nextIndex)
        }
    }
    
    private static func parseLiteralSequence(_ input: String, startingAt index: String.Index) -> (String, String.Index) {
        var result = ""
        var nextIndex = index
        
        while nextIndex < input.endIndex {
            let char = input[nextIndex]
            
            // Stop at pattern symbols
            if char == "." || char == "*" || char == "@" || char == "&" || char.isNumber {
                break
            }
            
            result.append(char)
            nextIndex = input.index(after: nextIndex)
        }
        
        return (result, nextIndex)
    }
    
    // MARK: - Restrictions Parsing
    
    private static func parseRestrictions(_ input: String) throws -> PatternRestrictions {
        var includes: [String: Int] = [:]
        var excludes: Set<String> = []
        var exclusiveRack: [String] = []
        var wildcardCount = 0
        var length: Int? = nil
        
        var i = input.startIndex
        
        while i < input.endIndex {
            let char = input[i]
            
            switch char {
            case "+":
                let (letters, nextIndex) = parseLetterGroup(input, startingAt: input.index(after: i))
                for letter in letters {
                    includes[letter, default: 0] += 1
                }
                i = nextIndex
                
            case "-":
                let (letters, nextIndex) = parseLetterGroup(input, startingAt: input.index(after: i))
                excludes.formUnion(letters)
                i = nextIndex
                
            case ":":
                let (lengthValue, nextIndex) = parseNumber(input, startingAt: input.index(after: i))
                length = lengthValue
                i = nextIndex
                
            case "?":
                wildcardCount += 1
                i = input.index(after: i)
                
            case " ", ",":
                // Skip whitespace and commas
                i = input.index(after: i)
                
            default:
                // Part of exclusive rack
                let (letters, nextIndex) = parseLetterGroup(input, startingAt: i)
                exclusiveRack.append(contentsOf: letters)
                i = nextIndex
            }
        }
        
        // Apply "leyes de los signos" (sign laws) 😄
        for (letter, _) in includes {
            if excludes.contains(letter) {
                excludes.remove(letter)
                // Keep in includes (net positive)
            }
        }
        
        return PatternRestrictions(
            includes: includes,
            excludes: excludes,
            exclusiveRack: exclusiveRack,
            wildcardCount: wildcardCount,
            length: length
        )
    }
    
    private static func parseLetterGroup(_ input: String, startingAt index: String.Index) -> ([String], String.Index) {
        var letters: [String] = []
        var i = index
        
        while i < input.endIndex {
            let char = input[i]
            
            // Stop at restriction symbols
            if char == "+" || char == "-" || char == ":" || char == "?" || char == " " || char == "," {
                break
            }
            
            // Handle numbered letters (2A, 3B, etc.)
            if char.isNumber {
                let (count, nextIndex) = parseNumber(input, startingAt: i)
                if nextIndex < input.endIndex {
                    let letter = String(input[nextIndex])
                    for _ in 0..<count {
                        letters.append(letter)
                    }
                    i = input.index(after: nextIndex)
                } else {
                    break
                }
            } else {
                letters.append(String(char))
                i = input.index(after: i)
            }
        }
        
        return (letters, i)
    }
    
    private static func parseNumber(_ input: String, startingAt index: String.Index) -> (Int, String.Index) {
        var numberString = ""
        var i = index
        
        while i < input.endIndex && input[i].isNumber {
            numberString.append(input[i])
            i = input.index(after: i)
        }
        
        return (Int(numberString) ?? 1, i)
    }
}

// MARK: - Error Types

enum PatternParseError: Error, LocalizedError {
    case emptyInput
    case invalidPattern(String)
    case invalidRestrictions(String)
    case conflictingRestrictions(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "El patrón no puede estar vacío"
        case .invalidPattern(let details):
            return "Patrón inválido: \(details)"
        case .invalidRestrictions(let details):
            return "Restricciones inválidas: \(details)"
        case .conflictingRestrictions(let details):
            return "Restricciones conflictivas: \(details)"
        case .unknownError(let details):
            return "Error desconocido: \(details)"
        }
    }
}