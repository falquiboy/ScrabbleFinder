import Foundation
import SwiftUI

// MARK: - Search Result Types

enum SearchMode {
    case validator
    case anagram
    case pattern
}

struct ValidationResult {
    let word: String
    let isValid: Bool
}

struct WildcardResult {
    let word: String
    let wildcardLetters: [Character]
    let wildcardPositions: [Int] // Positions of wildcard characters in the word
    let hooks: WordHooks? // Optional hooks for this word
}

struct AnagramResult {
    let word: String
    let hooks: WordHooks? // Optional hooks for this word
}

struct SearchResult {
    let mode: SearchMode
    let validationResults: [ValidationResult]
    let anagramResults: [AnagramResult]
    let wildcardResults: [WildcardResult]
    let patternResults: [String]
    
    static let empty = SearchResult(
        mode: .validator,
        validationResults: [],
        anagramResults: [],
        wildcardResults: [],
        patternResults: []
    )
}

// MARK: - Unified Search Model

class UnifiedSearchModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var query = ""
    @Published var searchResult = SearchResult.empty
    @Published var isLoading = false
    @Published var isTrieReady = false
    
    // MARK: - Private Properties
    private let dataManager = DataManager()
    
    // MARK: - Initialization
    
    init() {
        // Observe trie readiness
        dataManager.$isTrieReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTrieReady)
    }
    
    // MARK: - Search Mode Detection
    
    private func detectSearchMode(from input: String) -> SearchMode {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validator mode: contains spaces (multiple words)
        if trimmed.contains(" ") {
            return .validator
        }
        
        // Pattern mode: contains dots or specific pattern syntax
        if trimmed.contains(".") || trimmed.contains(",") || trimmed.contains("*") {
            return .pattern
        }
        
        // Default: anagram mode (includes wildcards with ?)
        return .anagram
    }
    
    // MARK: - Unified Search Entry Point
    
    func performSearch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResult = SearchResult.empty
            return
        }
        
        isLoading = true
        let mode = detectSearchMode(from: trimmedQuery)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let result: SearchResult
            
            switch mode {
            case .validator:
                result = self.performValidation(trimmedQuery)
            case .anagram:
                result = self.performAnagramSearch(trimmedQuery)
            case .pattern:
                result = self.performPatternSearch(trimmedQuery)
            }
            
            DispatchQueue.main.async {
                self.searchResult = result
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Validation Search
    
    private func performValidation(_ input: String) -> SearchResult {
        // Split input by non-letter characters (spaces, punctuation)
        let words = input.uppercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { !$0.isEmpty }
        
        let validationResults = words.map { word in
            ValidationResult(
                word: word,
                isValid: SpanishUtils.isValidSpanishInput(word) && 
                        dataManager.validateWord(word)
            )
        }
        
        return SearchResult(
            mode: .validator,
            validationResults: validationResults,
            anagramResults: [],
            wildcardResults: [],
            patternResults: []
        )
    }
    
    // MARK: - Anagram Search
    
    private func performAnagramSearch(_ input: String) -> SearchResult {
        print("🔍 Starting anagram search for: '\(input)'")
        // Process input to separate letters from wildcards
        var wildcardCount = 0
        var letters = ""
        
        // Count wildcards and extract letters
        for char in input.uppercased() {
            if char == "?" {
                wildcardCount += 1
            } else if char.isLetter {
                letters.append(char)
            }
        }
        
        print("🔍 Processed input: letters='\(letters)', wildcards=\(wildcardCount)")
        
        // Validate input (max 2 wildcards, valid Spanish letters)
        guard wildcardCount <= 2 && SpanishUtils.isValidSpanishInput(letters) else {
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: [],
                wildcardResults: [],
                patternResults: []
            )
        }
        
        // Handle different cases
        if wildcardCount == 0 {
            // Regular anagram search with hooks
            print("🔍 Performing regular anagram search")
            let anagramWords = dataManager.findAnagrams(for: letters)
            print("🔍 Found \(anagramWords.count) anagram words")
            let anagramResults = loadAnagramsWithHooks(anagramWords)
            print("🔍 Loaded \(anagramResults.count) anagram results with hooks")
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: anagramResults,
                wildcardResults: [],
                patternResults: []
            )
        } else {
            // Wildcard anagram search with hooks
            print("🔍 Performing wildcard search")
            let wildcardResults = performWildcardSearch(letters: letters, wildcardCount: wildcardCount)
            print("🔍 Found \(wildcardResults.count) wildcard results")
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: [],
                wildcardResults: wildcardResults,
                patternResults: []
            )
        }
    }
    
    private func performWildcardSearch(letters: String, wildcardCount: Int) -> [WildcardResult] {
        let normalizedLetters = SpanishUtils.normalize(letters)
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        
        var seen = Set<String>()
        var results: [WildcardResult] = []
        
        func processCandidate(_ candidate: String, _ substitutions: [Character]) {
            let alphagram = SpanishUtils.generateAlphagram(candidate)
            let matches = dataManager.findAnagramsByAlphagram(alphagram)
            
            for word in matches {
                let normalizedWord = SpanishUtils.normalize(word)
                if !seen.contains(normalizedWord) {
                    seen.insert(normalizedWord)
                    
                    // Calculate wildcard positions efficiently
                    let positions = calculateWildcardPositions(
                        originalLetters: letters, 
                        resultWord: word, 
                        substitutions: substitutions
                    )
                    
                    // Convert internal substitutions to display format
                    let displaySubs = substitutions.map { char in
                        SpanishUtils.denormalize(String(char)).first ?? char
                    }
                    
                    // Load hooks for this word (normalize for database lookup)
                    let normalizedWord = SpanishUtils.normalize(word)
                    let hooks = dataManager.getHooks(for: normalizedWord)
                    
                    results.append(WildcardResult(
                        word: word, 
                        wildcardLetters: displaySubs,
                        wildcardPositions: positions,
                        hooks: hooks
                    ))
                }
            }
        }
        
        // Generate combinations more efficiently
        generateWildcardCombinations(
            baseLetters: normalizedLetters,
            count: wildcardCount,
            letters: spanishLetters,
            processor: processCandidate
        )
        
        return results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
    }
    
    /// Loads anagrams with their hooks efficiently
    private func loadAnagramsWithHooks(_ words: [String]) -> [AnagramResult] {
        print("🔍 Loading hooks for \(words.count) words: \(words.prefix(5))")
        // Normalize words for database lookup
        let normalizedWords = words.map { SpanishUtils.normalize($0) }
        let hooksData = dataManager.getHooks(for: normalizedWords)
        print("🔍 Got hooks data for \(hooksData.count) words")
        
        return words.map { word in
            let normalizedWord = SpanishUtils.normalize(word)
            return AnagramResult(word: word, hooks: hooksData[normalizedWord])
        }
    }
    
    /// Efficiently generates wildcard combinations without nested loops
    private func generateWildcardCombinations(
        baseLetters: String,
        count: Int,
        letters: [Character],
        processor: (String, [Character]) -> Void
    ) {
        func generate(current: String, subs: [Character], remaining: Int) {
            if remaining == 0 {
                processor(current, subs)
                return
            }
            
            for letter in letters {
                generate(
                    current: current + String(letter),
                    subs: subs + [letter],
                    remaining: remaining - 1
                )
            }
        }
        
        generate(current: baseLetters, subs: [], remaining: count)
    }
    
    /// Calculates the positions of wildcard letters in the result word
    private func calculateWildcardPositions(
        originalLetters: String,
        resultWord: String,
        substitutions: [Character]
    ) -> [Int] {
        let originalNormalized = SpanishUtils.normalize(originalLetters).uppercased()
        let resultNormalized = SpanishUtils.normalize(resultWord).uppercased()
        
        // Convert to character arrays for easier manipulation
        let originalChars = Array(originalNormalized)
        var resultChars = Array(resultNormalized)
        var positions: [Int] = []
        
        // Remove original letters from result to find wildcard positions
        for char in originalChars {
            if let index = resultChars.firstIndex(of: char) {
                resultChars.remove(at: index)
            }
        }
        
        // Find positions of remaining characters (wildcards) in original word
        let wildcardChars = resultChars
        let resultUnits = SpanishUtils.splitIntoSpanishUnits(resultWord)
        
        for (unitIndex, unit) in resultUnits.enumerated() {
            let unitNormalized = SpanishUtils.normalize(unit).uppercased()
            if wildcardChars.contains(where: { String($0) == unitNormalized }) {
                positions.append(unitIndex)
            }
        }
        
        return positions
    }
    
    // MARK: - Pattern Search (Placeholder)
    
    private func performPatternSearch(_ input: String) -> SearchResult {
        // TODO: Implement pattern search logic
        // For now, return empty result
        return SearchResult(
            mode: .pattern,
            validationResults: [],
            anagramResults: [],
            wildcardResults: [],
            patternResults: []
        )
    }
    
    // MARK: - Helper Methods
    
    /// Clears current search results and query
    func clearSearch() {
        query = ""
        searchResult = SearchResult.empty
    }
    
    /// Returns formatted result count for display
    var resultCount: String {
        switch searchResult.mode {
        case .validator:
            let total = searchResult.validationResults.count
            let valid = searchResult.validationResults.filter(\.isValid).count
            return "\(valid)/\(total) válidas"
        case .anagram:
            let anagramCount = searchResult.anagramResults.count
            let wildcardCount = searchResult.wildcardResults.count
            if wildcardCount > 0 {
                return "\(wildcardCount) con wildcards"
            } else {
                return "\(anagramCount) anagramas"
            }
        case .pattern:
            return "\(searchResult.patternResults.count) patrones"
        }
    }
    
    /// Returns appropriate placeholder text based on detected mode
    var placeholderText: String {
        let detected = detectSearchMode(from: query)
        switch detected {
        case .validator:
            return "Escribe palabras separadas por espacio"
        case .anagram:
            return "Letras y ? para wildcards (ej: AMO?)"
        case .pattern:
            return "Patrón con puntos (ej: M...N)"
        }
    }
}