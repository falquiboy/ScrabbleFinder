import Foundation

// MARK: - Pattern Search Results

struct PatternSearchResult {
    let query: PatternQuery
    let wordsByLength: [Int: [String]]
    let totalCount: Int
    let maxLength: Int
    let minLength: Int
    let errorMessage: String?
    
    var isEmpty: Bool {
        return totalCount == 0
    }
    
    var hasLongWords: Bool {
        return maxLength > 8
    }
    
    var sortedLengths: [Int] {
        return wordsByLength.keys.sorted(by: >)
    }
    
    static let empty = PatternSearchResult(
        query: PatternQuery(
            pattern: PatternStructure(elements: [], rawPattern: ""),
            restrictions: PatternRestrictions(
                includes: [:], excludes: [], exclusiveRack: [],
                wildcardCount: 0, length: nil
            ),
            originalInput: ""
        ),
        wordsByLength: [:],
        totalCount: 0,
        maxLength: 0,
        minLength: 0,
        errorMessage: nil
    )
}

// MARK: - Pattern Search Model

class PatternSearchModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var query = ""
    @Published var searchResult = PatternSearchResult.empty
    @Published var isLoading = false
    @Published var showLongWords = false
    
    // MARK: - Private Properties
    private let dataManager = DataManager()
    
    // MARK: - Search Interface
    
    /// Performs pattern search based on current query
    func search() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResult = PatternSearchResult.empty
            return
        }
        
        isLoading = true
        
        // Parse the query
        switch PatternParser.parse(query) {
        case .success(let parsedQuery):
            performSearch(with: parsedQuery)
        case .failure(let error):
            searchResult = PatternSearchResult(
                query: PatternSearchResult.empty.query,
                wordsByLength: [:],
                totalCount: 0,
                maxLength: 0,
                minLength: 0,
                errorMessage: error.localizedDescription
            )
            isLoading = false
        }
    }
    
    // MARK: - Search Implementation
    
    private func performSearch(with query: PatternQuery) {
        // Convert pattern to regex
        let regex = buildRegex(from: query.pattern)
        
        // Get all words that match the pattern
        var matchingWords = findWordsMatching(regex: regex)
        
        // Apply restrictions
        matchingWords = applyRestrictions(to: matchingWords, restrictions: query.restrictions)
        
        // Group by length
        let wordsByLength = groupWordsByLength(matchingWords)
        
        // Calculate statistics
        let totalCount = matchingWords.count
        let lengths = wordsByLength.keys
        let maxLength = lengths.max() ?? 0
        let minLength = lengths.min() ?? 0
        
        // Create result
        searchResult = PatternSearchResult(
            query: query,
            wordsByLength: wordsByLength,
            totalCount: totalCount,
            maxLength: maxLength,
            minLength: minLength,
            errorMessage: nil
        )
        
        isLoading = false
    }
    
    // MARK: - Regex Building
    
    private func buildRegex(from pattern: PatternStructure) -> NSRegularExpression? {
        var regexPattern = "^"
        
        for element in pattern.elements {
            switch element {
            case .literal(let text):
                regexPattern += NSRegularExpression.escapedPattern(for: text)
                
            case .anyLetter:
                regexPattern += "[A-ZÁÉÍÓÚÜÑ]"
                
            case .anyLetters:
                regexPattern += "[A-ZÁÉÍÓÚÜÑ]*"
                
            case .vocal:
                regexPattern += "[AÁEÉIÍOÓUÚÜ]"
                
            case .vocalsAdjacent(let count):
                if count == 1 {
                    regexPattern += "[AÁEÉIÍOÓUÚÜ]"
                } else {
                    regexPattern += "[AÁEÉIÍOÓUÚÜ]{\(count)}"
                }
                
            case .consonant:
                regexPattern += "[BCDFGHJKLMNÑPQRSTVWXYZ]"
                
            case .consonantsAdjacent(let count):
                if count == 1 {
                    regexPattern += "[BCDFGHJKLMNÑPQRSTVWXYZ]"
                } else {
                    regexPattern += "[BCDFGHJKLMNÑPQRSTVWXYZ]{\(count)}"
                }
            }
        }
        
        regexPattern += "$"
        
        do {
            return try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
        } catch {
            print("❌ Error creating regex: \(error)")
            return nil
        }
    }
    
    // MARK: - Word Finding
    
    private func findWordsMatching(regex: NSRegularExpression?) -> [String] {
        guard let regex = regex else { return [] }
        
        // Use DataManager to get all words and filter by regex
        // This is a simplified approach - we might optimize later
        let allWords = dataManager.getAllWords()
        
        return allWords.filter { word in
            let denormalizedWord = SpanishUtils.denormalize(word)
            let range = NSRange(location: 0, length: denormalizedWord.utf16.count)
            return regex.firstMatch(in: denormalizedWord, options: [], range: range) != nil
        }
    }
    
    // MARK: - Restrictions Application
    
    private func applyRestrictions(to words: [String], restrictions: PatternRestrictions) -> [String] {
        return words.filter { word in
            return satisfiesRestrictions(word: word, restrictions: restrictions)
        }
    }
    
    private func satisfiesRestrictions(word: String, restrictions: PatternRestrictions) -> Bool {
        let denormalizedWord = SpanishUtils.denormalize(word)
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(denormalizedWord)
        
        // Length restriction
        if let requiredLength = restrictions.length {
            if wordUnits.count != requiredLength {
                return false
            }
        }
        
        // Exclusive rack restriction (most restrictive)
        if restrictions.hasExclusiveRack {
            return satisfiesExclusiveRack(wordUnits: wordUnits, restrictions: restrictions)
        }
        
        // Inclusion restrictions
        if restrictions.hasInclusions {
            if !satisfiesInclusions(wordUnits: wordUnits, includes: restrictions.includes) {
                return false
            }
        }
        
        // Exclusion restrictions
        if restrictions.hasExclusions {
            if !satisfiesExclusions(wordUnits: wordUnits, excludes: restrictions.excludes) {
                return false
            }
        }
        
        return true
    }
    
    private func satisfiesExclusiveRack(wordUnits: [String], restrictions: PatternRestrictions) -> Bool {
        let normalizedWordUnits = wordUnits.map { SpanishUtils.normalize($0).uppercased() }
        let normalizedRackUnits = restrictions.exclusiveRack.map { SpanishUtils.normalize($0).uppercased() }
        
        // Count available letters in rack
        var availableLetters = Dictionary(grouping: normalizedRackUnits) { $0 }
            .mapValues { $0.count }
        
        // Add wildcards as flexibility
        var remainingWildcards = restrictions.wildcardCount
        
        // Count required letters from word
        let requiredLetters = Dictionary(grouping: normalizedWordUnits) { $0 }
            .mapValues { $0.count }
        
        // Check if word can be formed with available letters + wildcards
        for (letter, requiredCount) in requiredLetters {
            let availableCount = availableLetters[letter] ?? 0
            let shortfall = requiredCount - availableCount
            
            if shortfall > 0 {
                if shortfall <= remainingWildcards {
                    remainingWildcards -= shortfall
                } else {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func satisfiesInclusions(wordUnits: [String], includes: [String: Int]) -> Bool {
        let normalizedWordUnits = wordUnits.map { SpanishUtils.normalize($0).uppercased() }
        let wordLetterCounts = Dictionary(grouping: normalizedWordUnits) { $0 }
            .mapValues { $0.count }
        
        for (letter, requiredCount) in includes {
            let normalizedLetter = SpanishUtils.normalize(letter).uppercased()
            let wordCount = wordLetterCounts[normalizedLetter] ?? 0
            if wordCount < requiredCount {
                return false
            }
        }
        
        return true
    }
    
    private func satisfiesExclusions(wordUnits: [String], excludes: Set<String>) -> Bool {
        let normalizedWordUnits = Set(wordUnits.map { SpanishUtils.normalize($0).uppercased() })
        let normalizedExcludes = Set(excludes.map { SpanishUtils.normalize($0).uppercased() })
        
        return normalizedWordUnits.isDisjoint(with: normalizedExcludes)
    }
    
    // MARK: - Helper Methods
    
    private func groupWordsByLength(_ words: [String]) -> [Int: [String]] {
        let denormalizedWords = words.map { SpanishUtils.denormalize($0) }
        
        let grouped = Dictionary(grouping: denormalizedWords) { word in
            SpanishUtils.splitIntoSpanishUnits(word).count
        }
        
        // Sort words within each group
        return grouped.mapValues { words in
            words.sorted { SpanishUtils.compareSpanishOrder($0, $1) }
        }
    }
    
    // MARK: - Result Summary
    
    var resultSummary: String {
        if searchResult.isEmpty {
            return "0 resultados"
        }
        
        if searchResult.totalCount == 1 {
            return "1 resultado"
        }
        
        return "\(searchResult.totalCount) resultados"
    }
    
    var shouldShowLongWordsToggle: Bool {
        return searchResult.hasLongWords
    }
    
    /// Gets filtered results based on current toggle state
    func getFilteredResults() -> [Int: [String]] {
        if showLongWords {
            return searchResult.wordsByLength
        } else {
            // Filter out words longer than 8 letters
            return searchResult.wordsByLength.filter { length, _ in
                length <= 8
            }
        }
    }
}