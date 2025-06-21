import Foundation
import SwiftUI

// MARK: - Pattern Search Types (simplified for PatternViewModel integration)

struct UnifiedPatternSearchResult {
    let query: String
    let wordsByLength: [Int: [String]]
    let totalCount: Int
    let maxLength: Int
    let minLength: Int
    let errorMessage: String?
    let hasExplicitLengthRestriction: Bool
    
    var isEmpty: Bool {
        return totalCount == 0
    }
    
    var hasLongWords: Bool {
        return maxLength > 8
    }
    
    var sortedLengths: [Int] {
        return wordsByLength.keys.sorted(by: >)
    }
}

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
    let originalRack: String // Original rack letters for highlighting logic
}

struct RelevantWildcardResult {
    let word: String
    let wildcardLetters: [Character]
    let wildcardPositions: [Int]
    let hooks: WordHooks?
    let originalRack: String
    let mediumHighValueLetters: [Character] // Letters ≥3 points from rack in this word
}

struct AnagramResult {
    let word: String
    let hooks: WordHooks? // Optional hooks for this word
}

struct ExtraLetterResult {
    let word: String
    let extraLetter: Character
    let hooks: WordHooks? // Optional hooks for this word
    let originalRack: String // Original rack letters for highlighting logic
}

struct SearchResult {
    let mode: SearchMode
    let validationResults: [ValidationResult]
    let anagramResults: [AnagramResult]
    let extraLetterResults: [ExtraLetterResult]
    let wildcardResults: [WildcardResult]
    let relevantWildcardResults: [RelevantWildcardResult] // New: strategic 1-wildcard results
    let subanagramsNoWildcard: [AnagramResult] // New: subanagrams without wildcards
    let subanagramsWithWildcard: [WildcardResult] // New: other subanagrams with 1 wildcard
    let patternResults: [String]
    let patternSearchResult: UnifiedPatternSearchResult? // New pattern search results
    let errorMessage: String? // Optional error message
    
    static let empty = SearchResult(
        mode: .validator,
        validationResults: [],
        anagramResults: [],
        extraLetterResults: [],
        wildcardResults: [],
        relevantWildcardResults: [],
        subanagramsNoWildcard: [],
        subanagramsWithWildcard: [],
        patternResults: [],
        patternSearchResult: nil,
        errorMessage: nil
    )
}

// MARK: - Unified Search Model

class UnifiedSearchModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var query = ""
    @Published var searchResult = SearchResult.empty
    @Published var isLoading = false
    @Published var isTrieReady = false
    @Published var isDataReady = false  // Tracks if any data source is ready
    @Published var patternShowLongWordsState = false
    
    // MARK: - Performance Toast
    @Published var showPerformanceToast = false
    @Published var performanceMessage = ""
    
    
    // MARK: - Anti-Cheating Feature
    @Published var shouldCollapseAnagramGroups = false
    
    // MARK: - Private Properties
    private let dataManager = DataManager()
    private var anagramViewModel: AnagramViewModel?
    private var patternViewModel: PatternViewModel?
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        // Initialize AnagramViewModel and PatternViewModel
        let anagramVM = AnagramViewModel()
        self.anagramViewModel = anagramVM
        self.patternViewModel = PatternViewModel(anagramModel: anagramVM)
        
        // Observe data readiness
        dataManager.$isTrieReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTrieReady)
        
        dataManager.$isDataReady
            .receive(on: DispatchQueue.main)
            .assign(to: &$isDataReady)
    }
    
    // MARK: - System Status
    
    /// Indicates if searches can be performed (any data source ready)
    var canPerformSearches: Bool {
        return dataManager.canPerformQueries
    }
    
    /// Current data source being used
    var currentDataSource: String {
        return dataManager.currentDataSource
    }
    
    // MARK: - Performance Toast
    
    /// Shows a performance toast with timing and result information
    private func showPerformanceToast(executionTime: TimeInterval, resultCount: Int, source: String, isCacheHit: Bool = false) {
        let timing = String(format: "%.1f", executionTime * 1000) // Convert to milliseconds
        
        let message: String
        if isCacheHit {
            message = "⚡ \(resultCount) resultados • <1ms • Cache"
        } else if executionTime < 0.01 {
            message = "🚀 \(resultCount) resultados • <10ms • \(source)"
        } else if executionTime < 0.05 {
            message = "✨ \(resultCount) resultados • \(timing)ms • \(source)"
        } else {
            message = "📊 \(resultCount) resultados • \(timing)ms • \(source)"
        }
        
        DispatchQueue.main.async {
            self.performanceMessage = message
            self.showPerformanceToast = true
            
            // Auto-hide after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.showPerformanceToast = false
            }
        }
    }
    
    
    // MARK: - Search Mode Detection
    
    private func detectSearchMode(from input: String) -> SearchMode {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for trailing spaces (validator mode trigger for single words)
        if input.hasSuffix(" ") || input.hasSuffix("\t") {
            // Only trigger validator mode if it's a single word with trailing space
            if !trimmed.contains(" ") {
                return .validator
            }
            // If it contains spaces internally, fall through to normal validation logic
        }
        
        // Validator mode: contains spaces (multiple words)
        if trimmed.contains(" ") {
            return .validator
        }
        
        // Pattern mode: contains pattern syntax characters
        // Look for dots, asterisks, commas, vowel (@), consonant (&), 
        // include (+), exclude (-), length (:) operators
        if trimmed.contains(".") || trimmed.contains("*") || 
           trimmed.contains("@") || trimmed.contains("&") ||
           trimmed.contains("+") || trimmed.contains("-") ||
           trimmed.contains(":") || trimmed.contains(",") {
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
        
        // Cancel any existing search
        searchTask?.cancel()
        
        isLoading = true
        let mode = detectSearchMode(from: query) // Use original query to preserve trailing spaces!
        
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Check if data is ready before performing search
            guard self.canPerformSearches else {
                await MainActor.run {
                    self.searchResult = SearchResult(
                        mode: mode,
                        validationResults: [],
                        anagramResults: [],
                        extraLetterResults: [],
                        wildcardResults: [],
                        relevantWildcardResults: [],
                        subanagramsNoWildcard: [],
                        subanagramsWithWildcard: [],
                        patternResults: [],
                        patternSearchResult: nil,
                        errorMessage: "Cargando datos... Inténtalo de nuevo."
                    )
                    self.isLoading = false
                    print("⚠️ Search attempted before data ready - current source: \(self.currentDataSource)")
                }
                return
            }
            
            let result: SearchResult
            
            // Check for cancellation before each operation
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.searchResult = SearchResult(
                        mode: mode,
                        validationResults: [],
                        anagramResults: [],
                        extraLetterResults: [],
                        wildcardResults: [],
                        relevantWildcardResults: [],
                        subanagramsNoWildcard: [],
                        subanagramsWithWildcard: [],
                        patternResults: [],
                        patternSearchResult: nil,
                        errorMessage: "Búsqueda cancelada"
                    )
                    self.isLoading = false
                }
                return
            }
            
            switch mode {
            case .validator:
                result = self.performValidation(trimmedQuery)
            case .anagram:
                result = self.performAnagramSearch(trimmedQuery)
            case .pattern:
                result = self.performPatternSearch(trimmedQuery)
            }
            
            // Check for cancellation before updating UI
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.searchResult = SearchResult(
                        mode: mode,
                        validationResults: [],
                        anagramResults: [],
                        extraLetterResults: [],
                        wildcardResults: [],
                        relevantWildcardResults: [],
                        subanagramsNoWildcard: [],
                        subanagramsWithWildcard: [],
                        patternResults: [],
                        patternSearchResult: nil,
                        errorMessage: "Búsqueda cancelada"
                    )
                    self.isLoading = false
                }
                return
            }
            
            await MainActor.run {
                self.searchResult = result
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Validation Search
    
    private func performValidation(_ input: String) -> SearchResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
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
        
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        let validCount = validationResults.filter(\.isValid).count
        
        // Show performance toast for validation
        showPerformanceToast(
            executionTime: executionTime,
            resultCount: validCount,
            source: "Validación",
            isCacheHit: false
        )
        
        return SearchResult(
            mode: .validator,
            validationResults: validationResults,
            anagramResults: [],
            extraLetterResults: [],
            wildcardResults: [],
            relevantWildcardResults: [],
            subanagramsNoWildcard: [],
            subanagramsWithWildcard: [],
            patternResults: [],
            patternSearchResult: nil,
            errorMessage: nil
        )
    }
    
    // MARK: - Anagram Search
    
    private func performAnagramSearch(_ input: String) -> SearchResult {
        print("🔍 Starting anagram search for: '\(input)'")
        
        // Check if this is a valid single word (anti-cheating feature)
        // Only apply anti-cheat if we're actually in anagram mode (not validator triggered by trailing space)
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedMode = detectSearchMode(from: input)
        let shouldCollapse = (detectedMode == .anagram) && checkIfValidWordAndShouldCollapse(trimmedInput)
        
        // Update collapse state on main thread
        DispatchQueue.main.async {
            self.shouldCollapseAnagramGroups = shouldCollapse
        }
        
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
        if shouldCollapse {
            print("🚫 Anti-cheat: Groups will be collapsed (valid word detected)")
        }
        
        // Validate input (max 2 wildcards, valid Spanish letters)
        if wildcardCount > 2 {
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: [],
                extraLetterResults: [],
                wildcardResults: [],
                relevantWildcardResults: [],
                subanagramsNoWildcard: [],
                subanagramsWithWildcard: [],
                patternResults: [],
                patternSearchResult: nil,
                errorMessage: "Búsqueda no permitida. Para búsquedas complejas utilice la sintaxis de patrón"
            )
        }
        
        guard SpanishUtils.isValidSpanishInput(letters) else {
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: [],
                extraLetterResults: [],
                wildcardResults: [],
                relevantWildcardResults: [],
                subanagramsNoWildcard: [],
                subanagramsWithWildcard: [],
                patternResults: [],
                patternSearchResult: nil,
                errorMessage: nil  // No error - just no results
            )
        }
        
        // Handle different cases
        if wildcardCount == 0 {
            // Regular anagram search with hooks and timing
            print("🔍 Performing regular anagram search")
            let normalizedLetters = SpanishUtils.normalize(letters)
            let alphagram = SpanishUtils.generateAlphagram(normalizedLetters)
            let searchResult = dataManager.findAnagramsWithTiming(alphagram)
            let anagramWords = searchResult.words
            print("🔍 Found \(anagramWords.count) anagram words")
            let anagramResults = loadAnagramsWithHooks(anagramWords)
            print("🔍 Loaded \(anagramResults.count) anagram results with hooks")
            
            // Show performance toast
            showPerformanceToast(
                executionTime: searchResult.executionTime,
                resultCount: anagramWords.count,
                source: searchResult.source,
                isCacheHit: searchResult.isCacheHit
            )
            
            // Extra letter search
            print("🔍 Performing extra letter search")
            let extraLetterResults = performExtraLetterSearch(letters: letters, excludeWords: anagramWords)
            print("🔍 Found \(extraLetterResults.count) extra letter results")
            
            // No error even if no results found - let UI handle empty lists
            let errorMessage: String? = nil
            
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: anagramResults,
                extraLetterResults: extraLetterResults,
                wildcardResults: [],
                relevantWildcardResults: [],
                subanagramsNoWildcard: [],
                subanagramsWithWildcard: [],
                patternResults: [],
                patternSearchResult: nil,
                errorMessage: errorMessage
            )
        } else {
            // Wildcard anagram search with hooks
            print("🔍 Performing wildcard search")
            let wildcardResults = performWildcardSearch(letters: letters, wildcardCount: wildcardCount)
            print("🔍 Found \(wildcardResults.count) wildcard results")
            
            // Generate relevant wildcard results if there are 2 wildcards
            var relevantWildcardResults: [RelevantWildcardResult] = []
            var subanagramsNoWildcard: [AnagramResult] = []
            var subanagramsWithWildcard: [WildcardResult] = []
            
            if wildcardCount >= 1 {
                print("🔍 Generating ALL shorter words (n-1 to 2 letters) with automatic classification")
                let subanagramResults = generateAndClassifyAllShorterWords(letters: letters)
                relevantWildcardResults = subanagramResults.relevant
                subanagramsNoWildcard = subanagramResults.noWildcard  
                subanagramsWithWildcard = subanagramResults.withWildcard
                print("🎯 Classified: \(relevantWildcardResults.count) relevant, \(subanagramsNoWildcard.count) no wildcard, \(subanagramsWithWildcard.count) other wildcard")
            }
            
            // Also perform extra letter search with wildcards
            print("🔍 Performing extra letter search with wildcards")
            let wildcardWords = wildcardResults.map { $0.word }
            let extraLetterResults = performExtraLetterSearchWithWildcards(letters: letters, wildcardCount: wildcardCount, excludeWords: wildcardWords)
            print("🔍 Found \(extraLetterResults.count) extra letter results with wildcards")
            
            // No error even if no results found - let UI handle empty lists
            let errorMessage: String? = nil
            
            return SearchResult(
                mode: .anagram,
                validationResults: [],
                anagramResults: [],
                extraLetterResults: extraLetterResults,
                wildcardResults: wildcardResults,
                relevantWildcardResults: relevantWildcardResults,
                subanagramsNoWildcard: subanagramsNoWildcard,
                subanagramsWithWildcard: subanagramsWithWildcard,
                patternResults: [],
                patternSearchResult: nil,
                errorMessage: errorMessage
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
                        hooks: hooks,
                        originalRack: letters
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
        
        return results.sorted { lhs, rhs in
            // Primary: Alphabetical order of wildcard letters
            let lhsWildcard = lhs.wildcardLetters.first?.uppercased() ?? ""
            let rhsWildcard = rhs.wildcardLetters.first?.uppercased() ?? ""
            let wildcardComparison = SpanishUtils.compareSpanishOrder(lhsWildcard, rhsWildcard)
            if lhsWildcard != rhsWildcard {
                return wildcardComparison
            }
            // Secondary: Spanish alphabetical order of words
            return SpanishUtils.compareSpanishOrder(lhs.word, rhs.word)
        }
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
    
    /// Performs extra letter search (adds one letter to the input)
    private func performExtraLetterSearch(letters: String, excludeWords: [String]) -> [ExtraLetterResult] {
        let normalizedLetters = SpanishUtils.normalize(letters)
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        let excludeSet = Set(excludeWords)
        
        var results: [ExtraLetterResult] = []
        
        for letter in spanishLetters {
            let candidateLetters = normalizedLetters + String(letter)
            let alphagram = SpanishUtils.generateAlphagram(candidateLetters)
            let matches = dataManager.findAnagramsByAlphagram(alphagram)
            
            for word in matches where !excludeSet.contains(word) {
                // Load hooks for this word
                let normalizedWord = SpanishUtils.normalize(word)
                let hooks = dataManager.getHooks(for: normalizedWord)
                
                // Convert internal letter back to display format
                let displayLetter = SpanishUtils.denormalize(String(letter)).first ?? letter
                
                results.append(ExtraLetterResult(
                    word: word,
                    extraLetter: displayLetter,
                    hooks: hooks,
                    originalRack: letters
                ))
            }
        }
        
        return results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
    }
    
    /// Performs extra letter search when wildcards are present
    private func performExtraLetterSearchWithWildcards(letters: String, wildcardCount: Int, excludeWords: [String]) -> [ExtraLetterResult] {
        let normalizedLetters = SpanishUtils.normalize(letters)
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        let excludeSet = Set(excludeWords)
        
        var results: [ExtraLetterResult] = []
        var seen = Set<String>()
        
        // For each possible wildcard combination + one extra letter
        func processWildcardCombination(_ wildcardLetters: [Character], _ extraLetter: Character) {
            let candidateLetters = normalizedLetters + wildcardLetters.map(String.init).joined() + String(extraLetter)
            let alphagram = SpanishUtils.generateAlphagram(candidateLetters)
            let matches = dataManager.findAnagramsByAlphagram(alphagram)
            
            for word in matches where !excludeSet.contains(word) && !seen.contains(word) {
                seen.insert(word)
                
                // Load hooks for this word
                let normalizedWord = SpanishUtils.normalize(word)
                let hooks = dataManager.getHooks(for: normalizedWord)
                
                // Convert internal letter back to display format
                let displayLetter = SpanishUtils.denormalize(String(extraLetter)).first ?? extraLetter
                
                results.append(ExtraLetterResult(
                    word: word,
                    extraLetter: displayLetter,
                    hooks: hooks,
                    originalRack: letters
                ))
            }
        }
        
        // Generate all wildcard combinations + one extra letter
        func generateWildcardCombinationsWithExtra(current: [Character], remaining: Int) {
            if remaining == 0 {
                // For each possible extra letter
                for extraLetter in spanishLetters {
                    processWildcardCombination(current, extraLetter)
                }
                return
            }
            
            for letter in spanishLetters {
                generateWildcardCombinationsWithExtra(
                    current: current + [letter],
                    remaining: remaining - 1
                )
            }
        }
        
        generateWildcardCombinationsWithExtra(current: [], remaining: wildcardCount)
        
        return results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
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
        let originalUnits = SpanishUtils.splitIntoSpanishUnits(originalLetters)
        let resultUnits = SpanishUtils.splitIntoSpanishUnits(resultWord)
        
        // Normalize both for comparison
        let originalNormalized = originalUnits.map { SpanishUtils.normalize($0).uppercased() }
        let resultNormalized = resultUnits.map { SpanishUtils.normalize($0).uppercased() }
        
        // Find which positions in result are wildcards (not in original)
        var usedOriginal = originalNormalized
        var positions: [Int] = []
        
        for (resultIndex, resultUnit) in resultNormalized.enumerated() {
            if let originalIndex = usedOriginal.firstIndex(of: resultUnit) {
                // This unit was in the original, remove it to avoid double counting
                usedOriginal.remove(at: originalIndex)
            } else {
                // This unit is a wildcard (not found in original)
                positions.append(resultIndex)
            }
        }
        
        return positions
    }
    
    // MARK: - Pattern Search
    
    private func hasExplicitLengthRestriction(_ input: String) -> Bool {
        // Check for explicit length restriction like ":7"
        let hasExplicitLength = input.contains(":") && input.range(of: #":\d+$"#, options: .regularExpression) != nil
        
        // Check for implicit fixed length (no variable-length wildcards "*")
        let hasImplicitFixedLength = hasImplicitFixedLength(input)
        
        return hasExplicitLength || hasImplicitFixedLength
    }
    
    private func hasImplicitFixedLength(_ input: String) -> Bool {
        // Extract pattern part (before comma if present)
        let patternPart: String
        if let commaIndex = input.firstIndex(of: ",") {
            patternPart = String(input[..<commaIndex])
        } else if input.hasPrefix("+") || input.hasPrefix("-") {
            // Pool-only query, no pattern restrictions
            return false
        } else {
            patternPart = input
        }
        
        // Remove length restriction if present for analysis
        let cleanPattern = patternPart.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
        
        // If pattern contains "*" (variable length wildcard), length is not fixed
        let containsVariableWildcard = cleanPattern.contains("*")
        
        // If pattern doesn't contain variable wildcards and is not empty, calculate implicit length
        if !containsVariableWildcard && !cleanPattern.isEmpty {
            // Calculate the implicit fixed length by counting all characters (letters, dots, ellipsis)
            let implicitLength = calculatePatternLength(cleanPattern)
            
            // Only consider it "fixed length" (disable toggle) if the length is <= 8
            // This allows ">8 letters" toggle to work for patterns like ".APODASTE" (9 letters)
            return implicitLength <= 8
        }
        
        return false
    }
    
    private func calculatePatternLength(_ pattern: String) -> Int {
        var length = 0
        let chars = Array(pattern.uppercased())
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            if char == "…" {
                // Ellipsis represents 3 positions
                length += 3
                i += 1
            } else if char == "." || char.isLetter {
                // Dot or letter represents 1 position
                length += 1
                i += 1
            } else {
                // Skip other characters
                i += 1
            }
        }
        
        return length
    }
    
    private func autoEnableLongWordsToggleIfNeeded(patternResult: UnifiedPatternSearchResult, input: String) {
        // Only auto-enable if toggle is available (not disabled due to fixed length)
        guard !patternResult.hasExplicitLengthRestriction else { return }
        
        // Only proceed if toggle is currently off
        guard !patternShowLongWordsState else { return }
        
        // Only proceed if there are results
        guard patternResult.totalCount > 0 else { return }
        
        // Check if there are NO results ≤8 letters AND there ARE results >8 letters
        let hasShortResults = patternResult.wordsByLength.keys.contains { $0 <= 8 }
        let hasLongResults = patternResult.wordsByLength.keys.contains { $0 > 8 }
        
        // Auto-enable toggle if only long results exist
        if !hasShortResults && hasLongResults {
            print("🔄 Auto-enabling >8 letters toggle: only found words >8 letters")
            setPatternShowLongWords(true)
        }
    }
    
    private func performPatternSearch(_ input: String) -> SearchResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let patternVM = patternViewModel else {
            let patternResult = UnifiedPatternSearchResult(
                query: input,
                wordsByLength: [:],
                totalCount: 0,
                maxLength: 0,
                minLength: 0,
                errorMessage: "PatternViewModel no inicializado",
                hasExplicitLengthRestriction: hasExplicitLengthRestriction(input)
            )
            
            return SearchResult(
                mode: .pattern,
                validationResults: [],
                anagramResults: [],
                extraLetterResults: [],
                wildcardResults: [],
                relevantWildcardResults: [],
                subanagramsNoWildcard: [],
                subanagramsWithWildcard: [],
                patternResults: [],
                patternSearchResult: patternResult,
                errorMessage: "PatternViewModel no inicializado"
            )
        }
        
        print("🔍 Using legacy PatternViewModel for search: \(input)")
        
        // Set query and perform search using PatternViewModel
        patternVM.query = input
        patternVM.search()
        
        // Convert PatternViewModel results to UnifiedPatternSearchResult
        let legacyResults = patternVM.resultsByLength
        
        // Check for parsing errors - if no results and input contains "?" in pattern part
        let inputUpper = input.uppercased()
        let patternPart: String
        if inputUpper.contains(",") {
            patternPart = String(inputUpper.split(separator: ",", maxSplits: 1)[0])
        } else {
            // No comma: entire input is pattern unless it starts with +/- or contains restrictions
            if inputUpper.hasPrefix("+") || inputUpper.hasPrefix("-") || 
               inputUpper.contains("2@") || inputUpper.contains("2&") {
                patternPart = "*" // Default pattern when only restrictions are present
            } else {
                patternPart = inputUpper
            }
        }
        
        // Check if error is due to wildcards in pattern
        if legacyResults.isEmpty && patternPart.contains("?") {
            let errorMessage = "Los comodines solo se admiten en el atril, no en el patrón. Utilice punto para representar cualquier letra individual en el patrón."
            
            let patternResult = UnifiedPatternSearchResult(
                query: input,
                wordsByLength: [:],
                totalCount: 0,
                maxLength: 0,
                minLength: 0,
                errorMessage: errorMessage,
                hasExplicitLengthRestriction: hasExplicitLengthRestriction(input)
            )
            
            return SearchResult(
                mode: .pattern,
                validationResults: [],
                anagramResults: [],
                extraLetterResults: [],
                wildcardResults: [],
                relevantWildcardResults: [],
                subanagramsNoWildcard: [],
                subanagramsWithWildcard: [],
                patternResults: [],
                patternSearchResult: patternResult,
                errorMessage: errorMessage
            )
        }
        
        // Check if error is due to +/- restrictions in pattern when comma is present
        if legacyResults.isEmpty && inputUpper.contains(",") {
            let hasIncludeExcludeInPattern = patternPart.contains("+") || patternPart.contains("-")
            if hasIncludeExcludeInPattern {
                let errorMessage = "Las restricciones +ABC-XYZ solo se admiten en el atril (después de la coma), no en el patrón."
                
                let patternResult = UnifiedPatternSearchResult(
                    query: input,
                    wordsByLength: [:],
                    totalCount: 0,
                    maxLength: 0,
                    minLength: 0,
                    errorMessage: errorMessage,
                    hasExplicitLengthRestriction: hasExplicitLengthRestriction(input)
                )
                
                return SearchResult(
                    mode: .pattern,
                    validationResults: [],
                    anagramResults: [],
                    extraLetterResults: [],
                    wildcardResults: [],
                    relevantWildcardResults: [],
                    subanagramsNoWildcard: [],
                    subanagramsWithWildcard: [],
                    patternResults: [],
                    patternSearchResult: patternResult,
                    errorMessage: errorMessage
                )
            }
        }
        
        // Check if error is due to mixed pattern + restrictions without comma
        if legacyResults.isEmpty && !inputUpper.contains(",") {
            // Remove length suffix for analysis
            var cleanInput = inputUpper
            if let range = cleanInput.range(of: #":\d+$"#, options: .regularExpression) {
                cleanInput.removeSubrange(range)
            }
            
            let hasPatternChars = cleanInput.contains { ch in
                ch.isLetter || ch == "." || ch == "*" || ch == "@" || ch == "&"
            }
            let hasPoolRestrictions = cleanInput.contains("+") || cleanInput.contains("-")
            let isNotPurePool = !cleanInput.hasPrefix("+") && !cleanInput.hasPrefix("-") && 
                               !cleanInput.contains("2@") && !cleanInput.contains("2&")
            
            if hasPatternChars && hasPoolRestrictions && isNotPurePool {
                let errorMessage = "Sintaxis inválida. No se puede mezclar patrón con restricciones sin coma. Use: [patrón],[pool]:[longitud]"
                
                let patternResult = UnifiedPatternSearchResult(
                    query: input,
                    wordsByLength: [:],
                    totalCount: 0,
                    maxLength: 0,
                    minLength: 0,
                    errorMessage: errorMessage,
                    hasExplicitLengthRestriction: hasExplicitLengthRestriction(input)
                )
                
                return SearchResult(
                    mode: .pattern,
                    validationResults: [],
                    anagramResults: [],
                    extraLetterResults: [],
                    wildcardResults: [],
                    relevantWildcardResults: [],
                    subanagramsNoWildcard: [],
                    subanagramsWithWildcard: [],
                    patternResults: [],
                    patternSearchResult: patternResult,
                    errorMessage: errorMessage
                )
            }
        }
        
        // Convert LegacyPatternSearchResult to simple strings
        var wordsByLength: [Int: [String]] = [:]
        var totalCount = 0
        
        for (length, results) in legacyResults {
            let words = results.map { SpanishUtils.denormalize($0.word) }
            wordsByLength[length] = words
            totalCount += words.count
        }
        
        let lengths = wordsByLength.keys
        let maxLength = lengths.max() ?? 0
        let minLength = lengths.min() ?? 0
        
        print("🎯 PatternViewModel found \(totalCount) results grouped by length")
        print("🎯 wordsByLength: \(wordsByLength.mapValues { $0.count })")
        print("🎯 maxLength: \(maxLength), minLength: \(minLength)")
        
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Show performance toast for pattern search
        showPerformanceToast(
            executionTime: executionTime,
            resultCount: totalCount,
            source: "Patrón",
            isCacheHit: false
        )
        
        // Create unified result
        let patternResult = UnifiedPatternSearchResult(
            query: input,
            wordsByLength: wordsByLength,
            totalCount: totalCount,
            maxLength: maxLength,
            minLength: minLength,
            errorMessage: nil,
            hasExplicitLengthRestriction: hasExplicitLengthRestriction(input)
        )
        
        // Auto-enable >8 letters toggle if pattern can generate any length results
        // but only has results >8 letters (no results ≤8)
        DispatchQueue.main.async {
            self.autoEnableLongWordsToggleIfNeeded(patternResult: patternResult, input: input)
        }
        
        return SearchResult(
            mode: .pattern,
            validationResults: [],
            anagramResults: [],
            extraLetterResults: [],
            wildcardResults: [],
            relevantWildcardResults: [],
            subanagramsNoWildcard: [],
            subanagramsWithWildcard: [],
            patternResults: [], // Legacy field - keep empty
            patternSearchResult: patternResult,
            errorMessage: nil
        )
    }
    
    // MARK: - Pattern Search Helpers (using PatternViewModel)
    
    // PatternViewModel handles all the heavy lifting now!
    
    private func groupWordsByLength(_ words: [String]) -> [Int: [String]] {
        let grouped = Dictionary(grouping: words) { word in
            SpanishUtils.splitIntoSpanishUnits(word).count
        }
        
        // Sort words within each group
        return grouped.mapValues { words in
            words.sorted { SpanishUtils.compareSpanishOrder($0, $1) }
        }
    }
    
    // MARK: - Anti-Cheating Helper
    
    /// Checks if input is a valid single word and should trigger group collapse
    private func checkIfValidWordAndShouldCollapse(_ input: String) -> Bool {
        // Only check if input contains only letters (no wildcards, spaces, or special chars)
        guard !input.isEmpty,
              input.allSatisfy({ $0.isLetter || $0.isWhitespace }),
              !input.contains(" "),
              !input.contains("?") else {
            return false
        }
        
        // Check if it's a valid Spanish word
        let normalizedInput = SpanishUtils.normalize(input.uppercased())
        return SpanishUtils.isValidSpanishInput(input) && dataManager.validateWord(normalizedInput)
    }
    
    // MARK: - Helper Methods
    
    /// Clears current search results and query
    func clearSearch() {
        query = ""
        searchResult = SearchResult.empty
        shouldCollapseAnagramGroups = false
    }
    
    /// Cancels current search if running
    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
        
        // Show cancellation message
        searchResult = SearchResult(
            mode: searchResult.mode,
            validationResults: [],
            anagramResults: [],
            extraLetterResults: [],
            wildcardResults: [],
            relevantWildcardResults: [],
            subanagramsNoWildcard: [],
            subanagramsWithWildcard: [],
            patternResults: [],
            patternSearchResult: nil,
            errorMessage: "Búsqueda cancelada"
        )
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
            let extraLetterCount = searchResult.extraLetterResults.count
            let wildcardCount = searchResult.wildcardResults.count
            let totalResults = anagramCount + extraLetterCount + wildcardCount
            
            if wildcardCount > 0 {
                return "\(wildcardCount) con wildcards"
            } else if extraLetterCount > 0 {
                return "\(totalResults) (\(extraLetterCount) +1 letra)"
            } else {
                return "\(anagramCount) anagramas"
            }
        case .pattern:
            if let patternResult = searchResult.patternSearchResult {
                return "\(patternResult.totalCount) resultados"
            } else {
                return "0 resultados"
            }
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
            return "Sintaxis: *.N,+AB-C:5 (patrón,filtros,longitud)"
        }
    }
    
    // MARK: - Public Helper Methods for Subanagrams
    
    /// Find anagrams by alphagram (public wrapper)
    func findAnagramsByAlphagram(_ alphagram: String) -> [String] {
        return dataManager.findAnagramsByAlphagram(alphagram)
    }
    
    /// Get hooks for words (public wrapper)
    func getHooks(for words: [String]) -> [String: WordHooks] {
        return dataManager.getHooks(for: words)
    }
    
    // MARK: - Pattern Search Public Methods
    
    /// Get showLongWords state from published property
    var patternShowLongWords: Bool {
        return patternShowLongWordsState
    }
    
    /// Set showLongWords state in both PatternViewModel and published property
    func setPatternShowLongWords(_ show: Bool) {
        print("🔍 setPatternShowLongWords: changing to \(show)")
        patternShowLongWordsState = show
        patternViewModel?.showLongWords = show
        
        // Note: Messages for different scenarios will be shown in results area
    }
    
    /// Check if pattern results have long words
    var patternHasLongWords: Bool {
        if let patternResult = searchResult.patternSearchResult {
            return patternResult.hasLongWords
        }
        return false
    }
    
    /// Check if pattern results ONLY have long words (no results ≤8 letters)
    var patternHasOnlyLongWords: Bool {
        guard let patternResult = searchResult.patternSearchResult else { return false }
        guard patternResult.totalCount > 0 else { return false }
        
        let hasShortResults = patternResult.wordsByLength.keys.contains { $0 <= 8 }
        let hasLongResults = patternResult.wordsByLength.keys.contains { $0 > 8 }
        
        return !hasShortResults && hasLongResults
    }
    
    /// Get filtered pattern results based on showLongWords toggle
    func getFilteredPatternResults() -> [Int: [String]] {
        guard let patternResult = searchResult.patternSearchResult else {
            print("🔍 getFilteredPatternResults: patternSearchResult is nil")
            return [:]
        }
        
        print("🔍 getFilteredPatternResults: patternShowLongWords = \(patternShowLongWords)")
        print("🔍 getFilteredPatternResults: original wordsByLength = \(patternResult.wordsByLength.mapValues { $0.count })")
        
        let result: [Int: [String]]
        if patternShowLongWords {
            // Show ONLY words longer than 8 letters (exclusive)
            result = patternResult.wordsByLength.filter { length, _ in
                length > 8
            }
        } else {
            // Show ONLY words 8 letters or shorter (exclusive)
            result = patternResult.wordsByLength.filter { length, _ in
                length <= 8
            }
        }
        
        print("🔍 getFilteredPatternResults: filtered result = \(result.mapValues { $0.count })")
        return result
    }
    
    // MARK: - Relevant Wildcard Search (Strategic 1-Wildcard Results)
    
    /// Generates strategic 1-wildcard results when 2 wildcards are available
    /// Shows words that use exactly 1 wildcard and have strategic letter placement
    /// IMPORTANT: Works with Spanish units (digraphs as single units)
    private func performRelevantWildcardSearch(letters: String) -> [RelevantWildcardResult] {
        print("🎯 Starting relevant wildcard search for letters: '\(letters)'")
        
        // Work with Spanish units instead of individual characters
        let rackUnits = SpanishUtils.splitIntoSpanishUnits(letters)
        let normalizedRackUnits = rackUnits.map { SpanishUtils.normalize($0) }
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        
        print("🎯 Rack units: \(rackUnits) -> normalized: \(normalizedRackUnits)")
        
        var results: [RelevantWildcardResult] = []
        var seen = Set<String>()
        
        // For each possible wildcard letter
        for wildcardLetter in spanishLetters {
            // For each unit we can remove from the rack
            for removeIndex in 0..<normalizedRackUnits.count {
                // Create new combination: rack without one unit + wildcard
                var candidateUnits = normalizedRackUnits
                candidateUnits.remove(at: removeIndex)
                candidateUnits.append(String(wildcardLetter))
                
                // Generate alphagram from the candidate units
                let candidateString = candidateUnits.joined()
                let alphagram = SpanishUtils.generateAlphagram(candidateString)
                let matches = dataManager.findAnagramsByAlphagram(alphagram)
                
                for word in matches where !seen.contains(word) {
                    seen.insert(word)
                    
                    // Calculate wildcard positions based on original rack vs result word
                    let wildcardPositions = calculateWildcardPositions(
                        originalLetters: letters,
                        resultWord: word,
                        substitutions: [wildcardLetter]
                    )
                    
                    // Check if this word is strategically relevant
                    let originalRackLetters = Array(SpanishUtils.normalize(letters))
                    if SpanishUtils.isRelevantWildcardWord(word, rackLetters: originalRackLetters, wildcardPositions: wildcardPositions) {
                        
                        // Convert internal wildcard letter to display format
                        let displayWildcard = SpanishUtils.denormalize(String(wildcardLetter)).first ?? wildcardLetter
                        
                        // Load hooks for this word
                        let normalizedWord = SpanishUtils.normalize(word)
                        let hooks = dataManager.getHooks(for: normalizedWord)
                        
                        // Find medium/high value letters from rack that appear in this word
                        let wordChars = Array(SpanishUtils.normalize(word))
                        let mediumHighValueLetters = originalRackLetters.filter { rackLetter in
                            wordChars.contains(rackLetter) && SpanishUtils.isMediumOrHighValue(rackLetter)
                        }
                        
                        results.append(RelevantWildcardResult(
                            word: word,
                            wildcardLetters: [displayWildcard],
                            wildcardPositions: wildcardPositions,
                            hooks: hooks,
                            originalRack: letters,
                            mediumHighValueLetters: mediumHighValueLetters
                        ))
                        
                        print("🎯 Added relevant result: '\(word)' with wildcard '\(displayWildcard)' at positions \(wildcardPositions)")
                    }
                }
            }
        }
        
        let sortedResults = results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
        print("🎯 Found \(sortedResults.count) strategic 1-wildcard results")
        
        return sortedResults
    }
    
    // MARK: - Unified Subanagrams Generation and Classification
    
    /// Generates ALL shorter words (n-1 to 2 letters) and automatically classifies them into 3 sections
    /// Approach: Generate everything first, then classify based on actual word properties
    /// IMPORTANT: Works with Spanish units (digraphs as single units)
    func generateAndClassifyAllShorterWords(letters: String) -> (relevant: [RelevantWildcardResult], noWildcard: [AnagramResult], withWildcard: [WildcardResult]) {
        print("🔍 Generating ALL shorter words from '\(letters)' and classifying")
        
        let rackUnits = SpanishUtils.splitIntoSpanishUnits(letters)
        let normalizedRackUnits = rackUnits.map { SpanishUtils.normalize($0) }
        let originalLength = normalizedRackUnits.count
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        
        var allWords: [(word: String, hasWildcard: Bool, wildcardLetters: [Character], wildcardPositions: [Int], hooks: WordHooks?)] = []
        var seen = Set<String>()
        
        print("🔍 Original rack units: \(rackUnits) (length: \(originalLength))")
        
        // Generate all shorter words from n-1 down to 2 letters
        for targetLength in 2..<originalLength {
            print("🔍 Generating words of length \(targetLength)")
            
            // 1. Generate words WITHOUT wildcards (using only rack letters)
            let rackCombinations = generateUnitCombinations(from: normalizedRackUnits, length: targetLength)
            for combination in rackCombinations {
                let combinationString = combination.joined()
                let alphagram = SpanishUtils.generateAlphagram(combinationString)
                
                if !seen.contains(alphagram) {
                    seen.insert(alphagram)
                    let matches = dataManager.findAnagramsByAlphagram(alphagram)
                    for word in matches {
                        let normalizedWord = SpanishUtils.normalize(word)
                        let hooks = dataManager.getHooks(for: normalizedWord)
                        allWords.append((word: word, hasWildcard: false, wildcardLetters: [], wildcardPositions: [], hooks: hooks))
                    }
                }
            }
            
            // 2. Generate words WITH exactly 1 wildcard
            // Need targetLength-1 rack units + 1 wildcard = targetLength total
            if targetLength > 1 {
                let rackUnitsNeeded = targetLength - 1
                if rackUnitsNeeded <= normalizedRackUnits.count {
                    let rackCombinations = generateUnitCombinations(from: normalizedRackUnits, length: rackUnitsNeeded)
                    
                    for rackCombination in rackCombinations {
                        for wildcardLetter in spanishLetters {
                            var candidateUnits = rackCombination
                            candidateUnits.append(String(wildcardLetter))
                            let candidateString = candidateUnits.joined()
                            let alphagram = SpanishUtils.generateAlphagram(candidateString)
                            
                            if !seen.contains(alphagram) {
                                seen.insert(alphagram)
                                let matches = dataManager.findAnagramsByAlphagram(alphagram)
                                for word in matches {
                                    let wildcardPositions = calculateWildcardPositions(
                                        originalLetters: letters,
                                        resultWord: word,
                                        substitutions: [wildcardLetter]
                                    )
                                    let displayWildcard = SpanishUtils.denormalize(String(wildcardLetter)).first ?? wildcardLetter
                                    let normalizedWord = SpanishUtils.normalize(word)
                                    let hooks = dataManager.getHooks(for: normalizedWord)
                                    
                                    allWords.append((
                                        word: word, 
                                        hasWildcard: true, 
                                        wildcardLetters: [displayWildcard], 
                                        wildcardPositions: wildcardPositions, 
                                        hooks: hooks
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("🔍 Generated \(allWords.count) total shorter words")
        
        // Now classify into 3 groups
        var relevantResults: [RelevantWildcardResult] = []
        var noWildcardResults: [AnagramResult] = []
        var withWildcardResults: [WildcardResult] = []
        
        let originalRackLetters = Array(SpanishUtils.normalize(letters))
        
        for wordData in allWords {
            if !wordData.hasWildcard {
                // No wildcard: goes to section 2
                noWildcardResults.append(AnagramResult(word: wordData.word, hooks: wordData.hooks))
            } else {
                // Has wildcard: check if relevant (4-6 letters + distance criteria)
                let wordLength = SpanishUtils.splitIntoSpanishUnits(wordData.word).count
                
                if wordLength >= 4 && wordLength <= 6 && 
                   SpanishUtils.isRelevantWildcardWord(wordData.word, rackLetters: originalRackLetters, wildcardPositions: wordData.wildcardPositions) {
                    // Relevant: goes to section 1
                    let mediumHighValueLetters = originalRackLetters.filter { rackLetter in
                        let wordChars = Array(SpanishUtils.normalize(wordData.word))
                        return wordChars.contains(rackLetter) && SpanishUtils.isMediumOrHighValue(rackLetter)
                    }
                    
                    relevantResults.append(RelevantWildcardResult(
                        word: wordData.word,
                        wildcardLetters: wordData.wildcardLetters,
                        wildcardPositions: wordData.wildcardPositions,
                        hooks: wordData.hooks,
                        originalRack: letters,
                        mediumHighValueLetters: mediumHighValueLetters
                    ))
                } else {
                    // Not relevant: goes to section 3
                    withWildcardResults.append(WildcardResult(
                        word: wordData.word,
                        wildcardLetters: wordData.wildcardLetters,
                        wildcardPositions: wordData.wildcardPositions,
                        hooks: wordData.hooks,
                        originalRack: letters
                    ))
                }
            }
        }
        
        // Filter out relevant results that can also be made without wildcards
        // Strategy: If you can make a word without a wildcard, preserve the wildcard for better opportunities
        let noWildcardWords = Set(noWildcardResults.map { $0.word })
        let filteredRelevantResults = relevantResults.filter { result in
            !noWildcardWords.contains(result.word)
        }
        
        print("🎯 Filtered out \(relevantResults.count - filteredRelevantResults.count) relevant words that can be made without wildcards")
        
        // Sort all results with wildcard letter as primary criteria (within each group/value)
        let sortedRelevant = filteredRelevantResults.sorted { lhs, rhs in
            // Primary: Alphabetical order of wildcard letters
            let lhsWildcard = lhs.wildcardLetters.first?.uppercased() ?? ""
            let rhsWildcard = rhs.wildcardLetters.first?.uppercased() ?? ""
            let wildcardComparison = SpanishUtils.compareSpanishOrder(lhsWildcard, rhsWildcard)
            if lhsWildcard != rhsWildcard {
                return wildcardComparison
            }
            // Secondary: Spanish alphabetical order of words
            return SpanishUtils.compareSpanishOrder(lhs.word, rhs.word)
        }
        let sortedNoWildcard = noWildcardResults.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
        // Filter out "other wildcard" results that can also be made without wildcards
        // Strategy: Same as relevant results - preserve wildcards for words that truly need them
        let filteredWithWildcardResults = withWildcardResults.filter { result in
            !noWildcardWords.contains(result.word)
        }
        
        print("🎯 Filtered out \(withWildcardResults.count - filteredWithWildcardResults.count) other wildcard words that can be made without wildcards")
        
        let sortedWithWildcard = filteredWithWildcardResults.sorted { lhs, rhs in
            // Primary: Alphabetical order of wildcard letters
            let lhsWildcard = lhs.wildcardLetters.first?.uppercased() ?? ""
            let rhsWildcard = rhs.wildcardLetters.first?.uppercased() ?? ""
            let wildcardComparison = SpanishUtils.compareSpanishOrder(lhsWildcard, rhsWildcard)
            if lhsWildcard != rhsWildcard {
                return wildcardComparison
            }
            // Secondary: Spanish alphabetical order of words
            return SpanishUtils.compareSpanishOrder(lhs.word, rhs.word)
        }
        
        print("🎯 Final classification:")
        print("  - Relevant (4-6 letters with distance ≥3): \(sortedRelevant.count)")
        print("  - No wildcard: \(sortedNoWildcard.count)")
        print("  - Other wildcard: \(sortedWithWildcard.count)")
        
        return (relevant: sortedRelevant, noWildcard: sortedNoWildcard, withWildcard: sortedWithWildcard)
    }
    
    /// Generates subanagrams using only rack letters (no wildcards)
    /// IMPORTANT: Works with Spanish units (digraphs as single units)
    private func generateSubanagramsWithoutWildcards(letters: String, originalLength: Int) -> [AnagramResult] {
        // Work with Spanish units instead of individual characters
        let rackUnits = SpanishUtils.splitIntoSpanishUnits(letters)
        let normalizedRackUnits = rackUnits.map { SpanishUtils.normalize($0) }
        var results: [AnagramResult] = []
        var seen = Set<String>()
        
        print("🔍 Generating subanagrams without wildcards from units: \(rackUnits)")
        
        // Generate all possible combinations of units (shorter than original)
        for targetLength in 2..<originalLength {
            let combinations = generateUnitCombinations(from: normalizedRackUnits, length: targetLength)
            
            for combination in combinations {
                let combinationString = combination.joined()
                let alphagram = SpanishUtils.generateAlphagram(combinationString)
                
                if !seen.contains(alphagram) {
                    seen.insert(alphagram)
                    
                    let matches = dataManager.findAnagramsByAlphagram(alphagram)
                    for word in matches {
                        let normalizedWord = SpanishUtils.normalize(word)
                        let hooks = dataManager.getHooks(for: normalizedWord)
                        results.append(AnagramResult(word: word, hooks: hooks))
                    }
                }
            }
        }
        
        print("🔍 Generated \(results.count) subanagrams without wildcards")
        return results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
    }
    
    /// Generates subanagrams using rack letters + exactly 1 wildcard
    /// IMPORTANT: Works with Spanish units (digraphs as single units)
    /// IMPORTANT: Excludes words that are already classified as "relevant" to avoid duplication
    private func generateSubanagramsWithOneWildcard(letters: String, originalLength: Int, relevantResults: [RelevantWildcardResult]) -> [WildcardResult] {
        // Work with Spanish units instead of individual characters
        let rackUnits = SpanishUtils.splitIntoSpanishUnits(letters)
        let normalizedRackUnits = rackUnits.map { SpanishUtils.normalize($0) }
        let spanishLetters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        var results: [WildcardResult] = []
        var seen = Set<String>()
        
        // Get relevant words to exclude them from this "others" section
        let relevantWords = Set(relevantResults.map { $0.word })
        
        print("🔍 Generating subanagrams with 1 wildcard from units: \(rackUnits)")
        print("🔍 Excluding \(relevantWords.count) relevant words from others section")
        
        // For each possible length shorter than original (in Spanish units)
        for targetLength in 2..<originalLength {
            // For each possible wildcard letter
            for wildcardLetter in spanishLetters {
                // For each unit we can remove from the rack
                for removeIndex in 0..<normalizedRackUnits.count {
                    // Create new combination: rack without one unit + wildcard
                    var candidateUnits = normalizedRackUnits
                    candidateUnits.remove(at: removeIndex)
                    
                    // Check if we need more units to reach target length
                    let currentLength = candidateUnits.count + 1 // +1 for wildcard
                    if currentLength != targetLength {
                        continue // Skip if this doesn't match our target length
                    }
                    
                    candidateUnits.append(String(wildcardLetter))
                    
                    // Generate alphagram from the candidate units
                    let candidateString = candidateUnits.joined()
                    let alphagram = SpanishUtils.generateAlphagram(candidateString)
                    
                    if !seen.contains(alphagram) {
                        seen.insert(alphagram)
                        
                        let matches = dataManager.findAnagramsByAlphagram(alphagram)
                        for word in matches {
                            // Skip words that are already classified as "relevant"
                            if relevantWords.contains(word) {
                                continue
                            }
                            
                            // Calculate wildcard positions
                            let wildcardPositions = calculateWildcardPositions(
                                originalLetters: letters,
                                resultWord: word,
                                substitutions: [wildcardLetter]
                            )
                            
                            // Convert internal wildcard letter to display format
                            let displayWildcard = SpanishUtils.denormalize(String(wildcardLetter)).first ?? wildcardLetter
                            
                            // Load hooks for this word
                            let normalizedWord = SpanishUtils.normalize(word)
                            let hooks = dataManager.getHooks(for: normalizedWord)
                            
                            results.append(WildcardResult(
                                word: word,
                                wildcardLetters: [displayWildcard],
                                wildcardPositions: wildcardPositions,
                                hooks: hooks,
                                originalRack: letters
                            ))
                        }
                    }
                }
            }
        }
        
        print("🔍 Generated \(results.count) subanagrams with 1 wildcard (excluding relevant)")
        return results.sorted { SpanishUtils.compareSpanishOrder($0.word, $1.word) }
    }
    
    /// Helper function to generate combinations of letters
    private func generateCombinations(from letters: [Character], length: Int) -> [[Character]] {
        guard length > 0 && length <= letters.count else { return [] }
        guard length > 1 else { return letters.map { [$0] } }
        
        var results: [[Character]] = []
        
        func backtrack(start: Int, current: [Character]) {
            if current.count == length {
                results.append(current)
                return
            }
            
            for i in start..<letters.count {
                backtrack(start: i + 1, current: current + [letters[i]])
            }
        }
        
        backtrack(start: 0, current: [])
        return results
    }
    
    /// Helper function to generate combinations of Spanish units (for digraph support)
    private func generateUnitCombinations(from units: [String], length: Int) -> [[String]] {
        guard length > 0 && length <= units.count else { return [] }
        guard length > 1 else { return units.map { [$0] } }
        
        var results: [[String]] = []
        
        func backtrack(start: Int, current: [String]) {
            if current.count == length {
                results.append(current)
                return
            }
            
            for i in start..<units.count {
                backtrack(start: i + 1, current: current + [units[i]])
            }
        }
        
        backtrack(start: 0, current: [])
        return results
    }
}
