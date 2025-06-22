import SwiftUI
import SafariServices

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - CGFloat Extension for Clamping
extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

struct UnifiedSearchView: View {
    @StateObject private var searchModel = UnifiedSearchModel()
    @FocusState private var isInputFocused: Bool
    @State private var showHooks = false
    @State private var allTilesExpanded = true
    @State private var extraLetterExpanded = true
    @State private var showSubanagrams = false
    @State private var subanagramsByLength: [Int: [String]] = [:]
    @State private var subanagramsWithHooks: [Int: [(String, WordHooks?)]] = [:]
    @State private var subanagramExpansionState: [Int: Bool] = [:]
    @State private var patternExpansionState: [Int: Bool] = [:]
    @State private var safariViewController: SFSafariViewController?
    
    // MARK: - Hamburger Menu State
    @State private var showHamburgerMenu = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // Header with hamburger menu and title
                HStack {
                    // Hamburger Menu Button
                    Button {
                        showHamburgerMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    
                    Spacer()
                    
                    // Fixed compact title
                    Text("+Léxico")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    // Invisible spacer for balance
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                
                // Search Input with external search button
                HStack(spacing: 8) {
                    TextField(searchModel.placeholderText, text: $searchModel.query)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .focused($isInputFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                        .overlay(
                            HStack {
                                Spacer()
                                // Clear/Cancel button with dual functionality
                                if !searchModel.query.isEmpty || searchModel.isLoading {
                                    Button {
                                        if searchModel.isLoading {
                                            // Cancel ongoing search
                                            searchModel.cancelSearch()
                                        } else {
                                            // Clear query and results
                                            searchModel.clearSearch()
                                        }
                                    } label: {
                                        Image(systemName: searchModel.isLoading ? "stop.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(searchModel.isLoading ? .red : .secondary)
                                            .font(.title3)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .padding(.trailing, 6)
                                }
                            }
                        )
                    
                    // External search button (magnifying glass)
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .disabled(searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                // Loading Indicator
                if searchModel.isLoading {
                    ProgressView("Buscando...")
                        .padding()
                }
                
                // Results Section
                if !searchModel.isLoading {
                    // Show error message if present
                    if let errorMessage = searchModel.searchResult.errorMessage {
                        VStack {
                            Text(errorMessage)
                                .font(.headline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    } else {
                        // Hooks toggle for anagram & pattern modes (validator hides)
                        // Show toggles even when there are no results (0 resultados) but hide for syntax errors
                        let shouldShowToggles = searchModel.searchResult.mode != .validator && 
                                              (searchModel.searchResult.errorMessage == nil || 
                                               searchModel.searchResult.errorMessage == "0 resultados")
                        
                        if shouldShowToggles {
                            VStack(spacing: 8) {
                                // Dynamic toggle: subanagrams for anagrams, long words for patterns
                                HStack {
                                    if searchModel.searchResult.mode == .anagram {
                                        Toggle("Mostrar palabras más cortas", isOn: $showSubanagrams)
                                            .onChange(of: showSubanagrams) { _, newValue in
                                                if newValue {
                                                    generateSubanagrams()
                                                }
                                            }
                                    } else if searchModel.searchResult.mode == .pattern {
                                        Toggle("Mostrar > 8 letras", isOn: Binding(
                                            get: { 
                                                let isFixedLength = hasFixedLength()
                                                // Auto-reset to false if disabled due to fixed length
                                                if isFixedLength && searchModel.patternShowLongWords {
                                                    DispatchQueue.main.async {
                                                        searchModel.setPatternShowLongWords(false)
                                                    }
                                                }
                                                return searchModel.patternShowLongWords && !isFixedLength
                                            },
                                            set: { searchModel.setPatternShowLongWords($0) }
                                        ))
                                        .disabled(hasFixedLength())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        // Display subanagrams view (with/without hooks) or main results (with/without hooks)
                        if showSubanagrams && searchModel.searchResult.mode == .anagram {
                            if showHooks {
                                subanagramsHooksResultsView
                            } else {
                                subanagramsResultsView
                            }
                        } else if showHooks && searchModel.searchResult.mode != .validator {
                            if searchModel.searchResult.mode == .pattern {
                                patternHooksResultsView
                            } else {
                                hooksResultsView
                            }
                        } else {
                            resultsView
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .navigationBarHidden(true)
            .onTapGesture {
                hideKeyboard()
            }
            .overlay(
                // Performance Toast Overlay (bottom, no animation)
                performanceToastView
                , alignment: .bottom
            )
            .sheet(isPresented: $showHamburgerMenu) {
                hamburgerMenuSheet
            }
        }
    }
    
    // MARK: - Dynamic Content
    
    @ViewBuilder
    private var resultsView: some View {
        switch searchModel.searchResult.mode {
        case .validator:
            validatorResultsView
        case .anagram:
            anagramResultsView
        case .pattern:
            patternResultsView
        }
    }
    
    // MARK: - Validator Results
    
    @ViewBuilder
    private var validatorResultsView: some View {
        if !searchModel.searchResult.validationResults.isEmpty {
            let allValid = searchModel.searchResult.validationResults.allSatisfy(\.isValid)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(searchModel.searchResult.validationResults, id: \.word) { result in
                    Text(result.word)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            openRAEDefinition(for: result.word)
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(allValid ? Color.green : Color.red)
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Anagram Results
    
    @ViewBuilder
    private var anagramResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    
                    // Note: Strategic wildcard results are now shown in subanagrams section when toggle is active
                    
                    // Group 1: Results with all tiles (including wildcards) - collapse if valid word detected
                    let allTilesCount = searchModel.searchResult.anagramResults.count + searchModel.searchResult.wildcardResults.count
                    DisclosureGroup(
                        allTilesCount > 0 ? "\(allTilesCount) resultados con todas las fichas" : "Resultados con todas las fichas",
                        isExpanded: Binding(
                            get: { 
                                // Start collapsed if anti-cheat is active, but allow user to expand
                                searchModel.shouldCollapseAnagramGroups ? false : allTilesExpanded 
                            },
                            set: { newValue in
                                allTilesExpanded = newValue
                                // If user manually expands, disable anti-cheat for this session
                                if newValue && searchModel.shouldCollapseAnagramGroups {
                                    searchModel.shouldCollapseAnagramGroups = false
                                }
                            }
                        )
                    ) {
                        if allTilesCount > 0 {
                            LazyVGrid(columns: [
                                GridItem(.fixed(165), spacing: 8),
                                GridItem(.fixed(165), spacing: 8)
                            ], spacing: 8) {
                                
                                // Regular anagram results
                                ForEach(searchModel.searchResult.anagramResults, id: \.word) { result in
                                    standardResultCard(word: result.word)
                                }
                                
                                // Wildcard results with highlighted wildcards
                                ForEach(getSortedWildcardResults(), id: \.word) { result in
                                    wildcardResultCard(result: result)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Text("Sin resultados")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    
                    // Group 2: Results with one additional letter - collapse if valid word detected
                    let extraLetterCount = searchModel.searchResult.extraLetterResults.count
                    DisclosureGroup(
                        extraLetterCount > 0 ? "\(extraLetterCount) resultados con una letra adicional" : "Resultados con una letra adicional",
                        isExpanded: Binding(
                            get: { 
                                // Start collapsed if anti-cheat is active, but allow user to expand
                                searchModel.shouldCollapseAnagramGroups ? false : extraLetterExpanded 
                            },
                            set: { newValue in
                                extraLetterExpanded = newValue
                                // If user manually expands, disable anti-cheat for this session
                                if newValue && searchModel.shouldCollapseAnagramGroups {
                                    searchModel.shouldCollapseAnagramGroups = false
                                }
                            }
                        )
                    ) {
                        if extraLetterCount > 0 {
                            LazyVGrid(columns: [
                                GridItem(.fixed(165), spacing: 8),
                                GridItem(.fixed(165), spacing: 8)
                            ], spacing: 8) {
                                
                                // Extra letter results sorted alphabetically by extra letter
                                ForEach(getSortedExtraLetterResults(), id: \.word) { result in
                                    extraLetterStandardCard(result: result)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Text("Sin resultados")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    // MARK: - Pattern Results
    
    @ViewBuilder
    private var patternResultsView: some View {
        if let patternResult = searchModel.searchResult.patternSearchResult, patternResult.totalCount > 0 {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    
                    // Get filtered results based on toggle
                    let filteredResults = searchModel.getFilteredPatternResults()
                    // Dynamic sorting: ≤8 letters = descending, >8 letters = ascending
                    let sortedLengths = searchModel.patternShowLongWords ? 
                        filteredResults.keys.sorted(by: <) :  // >8 letters: ascending
                        filteredResults.keys.sorted(by: >)    // ≤8 letters: descending
                    let _ = print("🔍 UI: filteredResults tiene \(filteredResults.count) longitudes: \(sortedLengths)")
                    let _ = print("🔍 UI: patternShowLongWords = \(searchModel.patternShowLongWords)")
                    
                    ForEach(sortedLengths, id: \.self) { length in
                        if let words = filteredResults[length], !words.isEmpty {
                            DisclosureGroup(
                                "\(length) letras (\(words.count))",
                                isExpanded: Binding(
                                    get: { patternExpansionState[length, default: true] },
                                    set: { patternExpansionState[length] = $0 }
                                )
                            ) {
                                // Words in a grid
                                LazyVGrid(columns: [
                                    GridItem(.fixed(165), spacing: 8),
                                    GridItem(.fixed(165), spacing: 8)
                                ], spacing: 8) {
                                    ForEach(words, id: \.self) { word in
                                        patternResultCard(word: word, originalPattern: searchModel.query)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.trailing, 16)
                        }
                    }
                    
                    // Show appropriate message based on toggle state and available results
                    if searchModel.patternShowLongWords && !searchModel.patternHasLongWords {
                        // Toggle is ON but no long words exist
                        Text("Sin resultados de más de 8 letras")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else if !searchModel.patternShowLongWords && searchModel.patternHasOnlyLongWords {
                        // Toggle is OFF but only long words exist (no short results)
                        Text("Solo hay resultados de más de 8 letras")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            }
        } else if let patternResult = searchModel.searchResult.patternSearchResult, patternResult.totalCount == 0 {
            VStack {
                Text("Sin resultados")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if let errorMessage = patternResult.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        isInputFocused = false
        hideKeyboard()
        
        // Reset subranagrams toggle to off for each new search and clear previous data
        showSubanagrams = false
        subanagramsByLength.removeAll()
        subanagramsWithHooks.removeAll()
        subanagramExpansionState.removeAll()
        
        searchModel.performSearch()
    }
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    /// Creates an AttributedString highlighting letters that exceed the original rack
    private func highlightWildcards(in result: WildcardResult) -> AttributedString {
        var attributed = AttributedString(result.word)
        
        // Use Spanish units for proper dígrafo handling
        let originalRackUnits = SpanishUtils.splitIntoSpanishUnits(result.originalRack)
        let normalizedOriginalRack = originalRackUnits.map { SpanishUtils.normalize($0).uppercased() }
        
        // Count available units in original rack
        var availableUnits: [String: Int] = [:]
        for unit in normalizedOriginalRack {
            availableUnits[unit, default: 0] += 1
        }
        
        // Count used units as we process the word
        var usedUnits: [String: Int] = [:]
        
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(result.word)
        var charPosition = 0
        
        for unit in wordUnits {
            let normalizedUnit = SpanishUtils.normalize(unit).uppercased()
            usedUnits[normalizedUnit, default: 0] += 1
            let availableCount = availableUnits[normalizedUnit, default: 0]
            
            // If this usage exceeds what was available in original rack, highlight it
            if usedUnits[normalizedUnit, default: 0] > availableCount {
                if let startPos = result.word.index(result.word.startIndex, offsetBy: charPosition, limitedBy: result.word.endIndex),
                   let endPos = result.word.index(startPos, offsetBy: unit.count, limitedBy: result.word.endIndex),
                   let startIdx = AttributedString.Index(startPos, within: attributed),
                   let endIdx = AttributedString.Index(endPos, within: attributed) {
                    
                    let range = startIdx..<endIdx
                    attributed[range].foregroundColor = .red
                    attributed[range].font = .title3.bold()
                }
            }
            charPosition += unit.count
        }
        
        return attributed
    }
    
    /// Creates an AttributedString highlighting wildcards and medium/high value letters for relevant results
    private func highlightRelevantWildcard(in result: RelevantWildcardResult) -> AttributedString {
        var attributed = AttributedString(result.word)
        
        // Use Spanish units for proper dígrafo handling
        let originalRackUnits = SpanishUtils.splitIntoSpanishUnits(result.originalRack)
        let normalizedOriginalRack = originalRackUnits.map { SpanishUtils.normalize($0).uppercased() }
        
        // Count available units in original rack
        var availableUnits: [String: Int] = [:]
        for unit in normalizedOriginalRack {
            availableUnits[unit, default: 0] += 1
        }
        
        // Count used units as we process the word
        var usedUnits: [String: Int] = [:]
        
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(result.word)
        var charPosition = 0
        
        for unit in wordUnits {
            let normalizedUnit = SpanishUtils.normalize(unit).uppercased()
            usedUnits[normalizedUnit, default: 0] += 1
            let availableCount = availableUnits[normalizedUnit, default: 0]
            
            if let startPos = result.word.index(result.word.startIndex, offsetBy: charPosition, limitedBy: result.word.endIndex),
               let endPos = result.word.index(startPos, offsetBy: unit.count, limitedBy: result.word.endIndex),
               let startIdx = AttributedString.Index(startPos, within: attributed),
               let endIdx = AttributedString.Index(endPos, within: attributed) {
                
                let range = startIdx..<endIdx
                
                // Check if this is a wildcard (usage exceeds available in rack)
                if usedUnits[normalizedUnit, default: 0] > availableCount {
                    // Wildcard letter - highlight in red and bold
                    attributed[range].foregroundColor = .red
                    attributed[range].font = .title3.bold()
                } else {
                    // Check if this is a medium/high value letter from the rack
                    let unitChar = normalizedUnit.first ?? Character("A")
                    if result.mediumHighValueLetters.contains(unitChar) {
                        // Strategic medium/high value letter - highlight in orange
                        attributed[range].foregroundColor = .orange
                        attributed[range].font = .title3.bold()
                    } else {
                        // Regular letter - normal styling
                        attributed[range].foregroundColor = .primary
                        attributed[range].font = .title3
                    }
                }
            }
            charPosition += unit.count
        }
        
        return attributed
    }
    
    /// Formats a word with external hooks displayed in lowercase
    private func formatWordWithHooks(_ result: AnagramResult) -> AttributedString {
        guard let hooks = result.hooks, hooks.hasExternalHooks else {
            return AttributedString(result.word)
        }
        
        let leftHooks = hooks.leftExternal.lowercased()
        let rightHooks = hooks.rightExternal.lowercased()
        let fullText = leftHooks + result.word + rightHooks
        
        var attributed = AttributedString(fullText)
        
        // Style the hooks in lowercase and gray
        if !leftHooks.isEmpty {
            let leftRange = attributed.startIndex..<attributed.index(attributed.startIndex, offsetByCharacters: leftHooks.count)
            attributed[leftRange].foregroundColor = .secondary
            attributed[leftRange].font = .title3
        }
        
        if !rightHooks.isEmpty {
            let rightStart = attributed.index(attributed.endIndex, offsetByCharacters: -rightHooks.count)
            let rightRange = rightStart..<attributed.endIndex
            attributed[rightRange].foregroundColor = .secondary
            attributed[rightRange].font = .title3
        }
        
        // Style the main word
        let wordStart = attributed.index(attributed.startIndex, offsetByCharacters: leftHooks.count)
        let wordEnd = attributed.index(attributed.endIndex, offsetByCharacters: -rightHooks.count)
        let wordRange = wordStart..<wordEnd
        attributed[wordRange].foregroundColor = .primary
        attributed[wordRange].font = .title3.bold()
        
        return attributed
    }

    // MARK: - Hooks Results View

    @ViewBuilder
    private var hooksResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                
                // Note: Strategic wildcard results are now shown in subanagrams section when toggle is active
                
                // Group 1: Results with all tiles (including wildcards)
                let allTilesCount = searchModel.searchResult.anagramResults.count + searchModel.searchResult.wildcardResults.count
                if allTilesCount > 0 {
                    DisclosureGroup(
                        "\(allTilesCount) resultados con todas las fichas",
                        isExpanded: $allTilesExpanded
                    ) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            // Regular anagrams
                            ForEach(searchModel.searchResult.anagramResults, id: \.word) { result in
                                hookRowView(word: result.word, hooks: result.hooks)
                            }
                            
                            // Wildcard results sorted by wildcard letter
                            ForEach(getSortedWildcardResults(), id: \.word) { result in
                                hookRowView(word: result.word, hooks: result.hooks, wildcardPositions: result.wildcardPositions)
                            }
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    }
                }
                
                // Group 2: Results with one additional letter
                if !searchModel.searchResult.extraLetterResults.isEmpty {
                    DisclosureGroup(
                        "\(searchModel.searchResult.extraLetterResults.count) resultados con una letra adicional",
                        isExpanded: $extraLetterExpanded
                    ) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            // Extra letter results sorted by extra letter
                            ForEach(getSortedExtraLetterResults(), id: \.word) { result in
                                hookRowView(word: result.word, hooks: result.hooks, extraLetter: result.extraLetter)
                            }
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    // MARK: - Result Cards for Two-Column Layout
    
    /// Standard result card (no highlighting)
    private func standardResultCard(word: String) -> some View {
        Text(word)
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 165, height: 36)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onTapGesture {
                openRAEDefinition(for: word)
            }
    }
    
    /// Standard anagram result card
    private func anagramResultCard(result: AnagramResult) -> some View {
        Text(result.word)
            .font(.title3)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
    }
    
    /// Extra letter result card using standard layout with wildcard highlighting
    private func extraLetterStandardCard(result: ExtraLetterResult) -> some View {
        Text(highlightExtraLetter(word: result.word, extraLetter: result.extraLetter, hooks: result.hooks, showHooks: false, originalRack: result.originalRack))
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 165, height: 36)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onTapGesture {
                openRAEDefinition(for: result.word)
            }
    }
    
    /// Wildcard result card with highlighted wildcards
    private func wildcardResultCard(result: WildcardResult) -> some View {
        Text(highlightWildcards(in: result))
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 165, height: 36)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onTapGesture {
                openRAEDefinition(for: result.word)
            }
    }
    
    /// Relevant wildcard result card with strategic highlighting
    private func relevantWildcardResultCard(result: RelevantWildcardResult) -> some View {
        Text(highlightRelevantWildcard(in: result))
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 165, height: 36)
            .background(Color.orange.opacity(0.1)) // Different background for strategic results
            .cornerRadius(8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onTapGesture {
                openRAEDefinition(for: result.word)
            }
    }
    
    // MARK: - Subanagrams Results View
    
    @ViewBuilder
    private var subanagramsResultsView: some View {
        // Check if we have wildcard subanagrams (3 sections) or regular subanagrams
        if hasWildcardSubanagrams {
            subanagramsWithWildcardsView
        } else {
            regularSubanagramsView
        }
    }
    
    /// Regular subanagrams view (existing functionality)
    @ViewBuilder
    private var regularSubanagramsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                
                // Display subanagrams grouped by length (descending order)
                let sortedLengths = subanagramsByLength.keys.sorted(by: >)
                
                ForEach(sortedLengths, id: \.self) { length in
                    if let words = subanagramsByLength[length], !words.isEmpty {
                        DisclosureGroup(
                            "\(length) letras (\(words.count))",
                            isExpanded: Binding(
                                get: { 
                                    // Start collapsed if anti-cheat is active, but allow user to expand
                                    searchModel.shouldCollapseAnagramGroups ? false : subanagramExpansionState[length, default: true] 
                                },
                                set: { newValue in
                                    subanagramExpansionState[length] = newValue
                                    // If user manually expands, disable anti-cheat for this session
                                    if newValue && searchModel.shouldCollapseAnagramGroups {
                                        searchModel.shouldCollapseAnagramGroups = false
                                    }
                                }
                            )
                        ) {
                            LazyVGrid(columns: [
                                GridItem(.fixed(165), spacing: 8),
                                GridItem(.fixed(165), spacing: 8)
                            ], spacing: 8) {
                                
                                ForEach(words, id: \.self) { word in
                                    standardResultCard(word: word)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    /// New: Subanagrams with wildcards view (3 sections)
    @ViewBuilder
    private var subanagramsWithWildcardsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                
                // Section 1: Relevant wildcard results (strategic) - grouped by length
                DisclosureGroup(
                    "Resultados relevantes con un comodín (\(searchModel.searchResult.relevantWildcardResults.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[1000, default: true] }, // Collapsible with unique key
                        set: { subanagramExpansionState[1000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.relevantWildcardResults.isEmpty {
                        Text("Sin resultados relevantes con un comodín")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedRelevant = Dictionary(grouping: searchModel.searchResult.relevantWildcardResults) { result in
                            // Group by total value of the entire word (wildcards = 0 points)
                            let wordUnits = SpanishUtils.splitIntoSpanishUnits(result.word)
                            let totalValue = wordUnits.enumerated().reduce(0) { sum, element in
                                let (index, unit) = element
                                // Wildcard positions have 0 value
                                if result.wildcardPositions.contains(index) {
                                    return sum + 0 // Wildcard = 0 points
                                } else {
                                    let normalizedUnit = SpanishUtils.normalize(unit)
                                    let unitChar = normalizedUnit.first ?? Character(" ")
                                    return sum + SpanishUtils.getLetterValue(unitChar)
                                }
                            }
                            return totalValue
                        }
                        let sortedValues = groupedRelevant.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedValues, id: \.self) { value in
                                if let results = groupedRelevant[value], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(value) puntos (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[value + 1100, default: true] }, // Unique key for relevant value groups
                                            set: { subanagramExpansionState[value + 1100] = $0 }
                                        )
                                    ) {
                                        LazyVGrid(columns: [
                                            GridItem(.fixed(165), spacing: 8),
                                            GridItem(.fixed(165), spacing: 8)
                                        ], spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                wildcardResultCard(result: WildcardResult(
                                                    word: result.word,
                                                    wildcardLetters: result.wildcardLetters,
                                                    wildcardPositions: result.wildcardPositions,
                                                    hooks: result.hooks,
                                                    originalRack: result.originalRack
                                                ))
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove orange special highlighting
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                
                // Section 2: Subanagrams without wildcards
                DisclosureGroup(
                    "Sin comodines (\(searchModel.searchResult.subanagramsNoWildcard.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[2000, default: true] }, // Unique key for section
                        set: { subanagramExpansionState[2000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.subanagramsNoWildcard.isEmpty {
                        Text("Sin subanagramas disponibles sin comodines")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedNoWildcard = Dictionary(grouping: searchModel.searchResult.subanagramsNoWildcard) { result in
                            SpanishUtils.splitIntoSpanishUnits(result.word).count
                        }
                        let sortedLengths = groupedNoWildcard.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedLengths, id: \.self) { length in
                                if let results = groupedNoWildcard[length], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(length) letras (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[length, default: true] },
                                            set: { subanagramExpansionState[length] = $0 }
                                        )
                                    ) {
                                        LazyVGrid(columns: [
                                            GridItem(.fixed(165), spacing: 8),
                                            GridItem(.fixed(165), spacing: 8)
                                        ], spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                standardResultCard(word: result.word)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove blue highlighting like other sections
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                
                // Section 3: Other subanagrams with 1 wildcard
                DisclosureGroup(
                    "Otras con un comodín (\(searchModel.searchResult.subanagramsWithWildcard.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[3000, default: true] }, // Now expanded by default like other sections
                        set: { subanagramExpansionState[3000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.subanagramsWithWildcard.isEmpty {
                        Text("Sin otras opciones con un comodín")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedWithWildcard = Dictionary(grouping: searchModel.searchResult.subanagramsWithWildcard) { result in
                            SpanishUtils.splitIntoSpanishUnits(result.word).count
                        }
                        let sortedLengths = groupedWithWildcard.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedLengths, id: \.self) { length in
                                if let results = groupedWithWildcard[length], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(length) letras (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[length + 1000, default: true] }, // Expanded by default like other sections
                                            set: { subanagramExpansionState[length + 1000] = $0 }
                                        )
                                    ) {
                                        LazyVGrid(columns: [
                                            GridItem(.fixed(165), spacing: 8),
                                            GridItem(.fixed(165), spacing: 8)
                                        ], spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                wildcardResultCard(result: result)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove red special highlighting
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    /// Helper to determine if we have wildcard subanagrams
    private var hasWildcardSubanagrams: Bool {
        return !searchModel.searchResult.relevantWildcardResults.isEmpty ||
               !searchModel.searchResult.subanagramsNoWildcard.isEmpty ||
               !searchModel.searchResult.subanagramsWithWildcard.isEmpty
    }
    
    // MARK: - Subanagrams with Hooks Results View
    
    @ViewBuilder
    private var subanagramsHooksResultsView: some View {
        // Check if we have wildcard subanagrams (3 sections) or regular subanagrams
        if hasWildcardSubanagrams {
            subanagramsWithWildcardsHooksView
        } else {
            regularSubanagramsHooksView
        }
    }
    
    /// Regular subanagrams with hooks view (existing functionality)
    @ViewBuilder
    private var regularSubanagramsHooksView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                
                // Display subanagrams with hooks grouped by length (descending order)
                let sortedLengths = subanagramsWithHooks.keys.sorted(by: >)
                
                ForEach(sortedLengths, id: \.self) { length in
                    if let wordsWithHooks = subanagramsWithHooks[length], !wordsWithHooks.isEmpty {
                        DisclosureGroup(
                            "\(length) letras (\(wordsWithHooks.count))",
                            isExpanded: Binding(
                                get: { 
                                    // Start collapsed if anti-cheat is active, but allow user to expand
                                    searchModel.shouldCollapseAnagramGroups ? false : subanagramExpansionState[length, default: true] 
                                },
                                set: { newValue in
                                    subanagramExpansionState[length] = newValue
                                    // If user manually expands, disable anti-cheat for this session
                                    if newValue && searchModel.shouldCollapseAnagramGroups {
                                        searchModel.shouldCollapseAnagramGroups = false
                                    }
                                }
                            )
                        ) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(wordsWithHooks.enumerated()), id: \.offset) { _, wordHookPair in
                                    hookRowView(word: wordHookPair.0, hooks: wordHookPair.1)
                                }
                            }
                        }
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    /// New: Subanagrams with wildcards hooks view (3 sections)
    @ViewBuilder
    private var subanagramsWithWildcardsHooksView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                
                // Section 1: Relevant wildcard results (strategic) - grouped by length
                DisclosureGroup(
                    "Resultados relevantes con un comodín (\(searchModel.searchResult.relevantWildcardResults.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[1000, default: true] }, // Collapsible with unique key
                        set: { subanagramExpansionState[1000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.relevantWildcardResults.isEmpty {
                        Text("Sin resultados relevantes con un comodín")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedRelevant = Dictionary(grouping: searchModel.searchResult.relevantWildcardResults) { result in
                            // Group by total value of the entire word (wildcards = 0 points)
                            let wordUnits = SpanishUtils.splitIntoSpanishUnits(result.word)
                            let totalValue = wordUnits.enumerated().reduce(0) { sum, element in
                                let (index, unit) = element
                                // Wildcard positions have 0 value
                                if result.wildcardPositions.contains(index) {
                                    return sum + 0 // Wildcard = 0 points
                                } else {
                                    let normalizedUnit = SpanishUtils.normalize(unit)
                                    let unitChar = normalizedUnit.first ?? Character(" ")
                                    return sum + SpanishUtils.getLetterValue(unitChar)
                                }
                            }
                            return totalValue
                        }
                        let sortedValues = groupedRelevant.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedValues, id: \.self) { value in
                                if let results = groupedRelevant[value], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(value) puntos (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[value + 1100, default: true] }, // Unique key for relevant value groups
                                            set: { subanagramExpansionState[value + 1100] = $0 }
                                        )
                                    ) {
                                        LazyVStack(alignment: .leading, spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                hookRowView(word: result.word, hooks: result.hooks, wildcardPositions: result.wildcardPositions)
                                            }
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove orange special highlighting
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                
                // Section 2: Subanagrams without wildcards
                DisclosureGroup(
                    "Sin comodines (\(searchModel.searchResult.subanagramsNoWildcard.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[2000, default: true] }, // Unique key for section
                        set: { subanagramExpansionState[2000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.subanagramsNoWildcard.isEmpty {
                        Text("Sin subanagramas disponibles sin comodines")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedNoWildcard = Dictionary(grouping: searchModel.searchResult.subanagramsNoWildcard) { result in
                            SpanishUtils.splitIntoSpanishUnits(result.word).count
                        }
                        let sortedLengths = groupedNoWildcard.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedLengths, id: \.self) { length in
                                if let results = groupedNoWildcard[length], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(length) letras (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[length, default: true] },
                                            set: { subanagramExpansionState[length] = $0 }
                                        )
                                    ) {
                                        LazyVStack(alignment: .leading, spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                hookRowView(word: result.word, hooks: result.hooks)
                                            }
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove blue highlighting like other sections
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                
                // Section 3: Other subanagrams with 1 wildcard
                DisclosureGroup(
                    "Otras con un comodín (\(searchModel.searchResult.subanagramsWithWildcard.count))",
                    isExpanded: Binding(
                        get: { subanagramExpansionState[3000, default: true] }, // Now expanded by default like other sections
                        set: { subanagramExpansionState[3000] = $0 }
                    )
                ) {
                    if searchModel.searchResult.subanagramsWithWildcard.isEmpty {
                        Text("Sin otras opciones con un comodín")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        let groupedWithWildcard = Dictionary(grouping: searchModel.searchResult.subanagramsWithWildcard) { result in
                            SpanishUtils.splitIntoSpanishUnits(result.word).count
                        }
                        let sortedLengths = groupedWithWildcard.keys.sorted(by: >)
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedLengths, id: \.self) { length in
                                if let results = groupedWithWildcard[length], !results.isEmpty {
                                    DisclosureGroup(
                                        "\(length) letras (\(results.count))",
                                        isExpanded: Binding(
                                            get: { subanagramExpansionState[length + 1000, default: true] }, // Expanded by default like other sections
                                            set: { subanagramExpansionState[length + 1000] = $0 }
                                        )
                                    ) {
                                        LazyVStack(alignment: .leading, spacing: 8) {
                                            ForEach(results, id: \.word) { result in
                                                hookRowView(word: result.word, hooks: result.hooks, wildcardPositions: result.wildcardPositions)
                                            }
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary) // Remove red special highlighting
                                }
                            }
                        }
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    // MARK: - Pattern Hooks Results
    
    @ViewBuilder
    private var patternHooksResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                patternHooksContent
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    @ViewBuilder
    private var patternHooksContent: some View {
        let filteredResults = searchModel.getFilteredPatternResults()
        // Dynamic sorting: ≤8 letters = descending, >8 letters = ascending
        let sortedLengths = searchModel.patternShowLongWords ? 
            filteredResults.keys.sorted(by: <) :  // >8 letters: ascending
            filteredResults.keys.sorted(by: >)    // ≤8 letters: descending
        
        ForEach(sortedLengths, id: \.self) { length in
            if let words = filteredResults[length], !words.isEmpty {
                patternHooksGroup(length: length, words: words)
            }
        }
    }
    
    @ViewBuilder
    private func patternHooksGroup(length: Int, words: [String]) -> some View {
        DisclosureGroup(
            "\(length) letras (\(words.count))",
            isExpanded: Binding(
                get: { patternExpansionState[length, default: true] },
                set: { patternExpansionState[length] = $0 }
            )
        ) {
            LazyVStack(alignment: .leading, spacing: 8) {
                let normalizedWords = words.map { SpanishUtils.normalize($0) }
                let hooksData = searchModel.getHooks(for: normalizedWords)
                
                ForEach(words, id: \.self) { word in
                    let normalizedWord = SpanishUtils.normalize(word)
                    let hooks = hooksData[normalizedWord]
                    patternHookRowView(word: word, hooks: hooks, originalPattern: searchModel.query)
                }
            }
        }
        .font(.headline)
        .fontWeight(.bold)
        .foregroundColor(.black)
    }
    
    // MARK: - Pattern Result Cards
    
    /// Pattern result card with highlighting (letters from pattern = black, fill letters = blue)
    private func patternResultCard(word: String, originalPattern: String) -> some View {
        let highlightedText = highlightPatternWord(word: word, pattern: originalPattern)
        
        return highlightedText
            .font(.title3)
            .fontWeight(.medium)
            .frame(width: 165, height: 36)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .lineLimit(1)
            .onTapGesture {
                openRAEDefinition(for: word)
            }
    }
    
    /// Pattern hook row view with highlighting (exact copy of hookRowView but with pattern highlighting)
    private func patternHookRowView(word: String, hooks: WordHooks?, originalPattern: String) -> some View {
        let wordLength = word.count
        
        // Count actual hooks for dynamic sizing
        let leftHookCount = SpanishUtils.splitIntoSpanishUnits(SpanishUtils.denormalize(hooks?.leftExternal ?? "")).count
        let rightHookCount = SpanishUtils.splitIntoSpanishUnits(SpanishUtils.denormalize(hooks?.rightExternal ?? "")).count
        
        // Pre-calculate dynamic height based on estimated rows
        let estimatedMaxRows = max(
            calculateRows(hookCount: leftHookCount, availableWidth: 120), // Estimate
            calculateRows(hookCount: rightHookCount, availableWidth: 120)
        )
        let dynamicHeight: CGFloat = max(36, CGFloat(estimatedMaxRows) * 26 + 10) // Minimized for maximum space efficiency
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width - 24 // Account for padding
            
            // DYNAMIC sizing based on actual hook count and word length
            let maxHooksPerSide = max(leftHookCount, rightHookCount)
            
            let hookColumnWidth: CGFloat = {
                // Calculate needed width based on actual hooks (always 4 per row)
                let hooksPerRow = maxHooksPerSide <= 2 ? maxHooksPerSide : 4
                // Rows calculation not needed for width, only for height calculation elsewhere
                let baseWidth = CGFloat(hooksPerRow) * 28 + CGFloat(max(0, hooksPerRow - 1)) * 2 // hooks + spacing
                
                // Minimum width for visual consistency, maximum for screen limits
                return max(baseWidth, 60).clamped(to: 40...140)
            }()
            
            let wordColumnWidth: CGFloat = {
                // Dynamic word width based on length and available space
                let idealWordWidth = max(CGFloat(wordLength) * 12, 60) // Base calculation
                let remainingWidth = availableWidth - (2 * hookColumnWidth) - 8
                
                // Smart allocation: give more space to longer words, less to shorter ones
                if wordLength <= 3 {
                    return max(60, min(idealWordWidth, remainingWidth * 0.3)) // Short words get less space
                } else if wordLength <= 6 {
                    return max(80, min(idealWordWidth, remainingWidth * 0.5)) // Medium words get balanced space
                } else {
                    return max(100, min(idealWordWidth, remainingWidth * 0.7)) // Long words get priority
                }
            }()
            
            let totalWidth = hookColumnWidth + wordColumnWidth + hookColumnWidth + 8 // Include spacing
            
            HStack(alignment: .center, spacing: 4) {
                // Left external hooks
                flexibleHooksView(
                    hooks: hooks?.leftExternal ?? "",
                    alignment: .trailing,
                    wordLength: wordLength,
                    availableWidth: hookColumnWidth
                )
                .frame(width: hookColumnWidth, alignment: .trailing)
                
                // Center: word with pattern highlighting + internal hooks - adaptive sizing for long words
                Text(highlightPatternWordWithInternalHooks(word: word, pattern: originalPattern, hooks: hooks))
                    .font(.title3)
                    .fontWeight(.bold)
                    .frame(width: wordColumnWidth, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5) // Allow shrinking for very long words
                
                // Right external hooks
                flexibleHooksView(
                    hooks: hooks?.rightExternal ?? "",
                    alignment: .leading,
                    wordLength: wordLength,
                    availableWidth: hookColumnWidth
                )
                .frame(width: hookColumnWidth, alignment: .leading)
            }
            .frame(width: totalWidth)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(height: dynamicHeight) // Dynamic height based on hook rows
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            openRAEDefinition(for: word)
        }
    }
    
    /// Highlight word based on pattern: pattern letters = blue, fill letters = black
    private func highlightPatternWord(word: String, pattern: String) -> Text {
        // Extract the core pattern (before comma if present)
        let corePattern = pattern.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? pattern
        
        // Get highlighting map for each character position
        let highlightMap = getPatternHighlightMap(word: word, pattern: corePattern)
        
        // Split into Spanish units and apply highlighting
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(word)
        var result = Text("")
        
        for (index, unit) in wordUnits.enumerated() {
            let isPatternLetter = highlightMap[index] ?? false
            let color: Color = isPatternLetter ? .blue : .black // Inverted: blue = pattern, black = fill
            
            let unitText = Text(unit).foregroundColor(color)
            result = result + unitText
        }
        
        return result
    }
    
    /// Highlight word with pattern colors and internal hooks styling
    private func highlightPatternWordWithInternalHooks(word: String, pattern: String, hooks: WordHooks?) -> AttributedString {
        // Start with basic AttributedString
        var attributed = AttributedString(word)
        
        // Get pattern highlight map
        let corePattern = pattern.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? pattern
        let highlightMap = getPatternHighlightMap(word: word, pattern: corePattern)
        
        // Split into Spanish units for proper processing
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(word)
        var charPosition = 0
        
        for (unitIndex, unit) in wordUnits.enumerated() {
            if let startPos = word.index(word.startIndex, offsetBy: charPosition, limitedBy: word.endIndex),
               let endPos = word.index(startPos, offsetBy: unit.count, limitedBy: word.endIndex),
               let startIdx = AttributedString.Index(startPos, within: attributed),
               let endIdx = AttributedString.Index(endPos, within: attributed) {
                
                let range = startIdx..<endIdx
                
                // Determine base color from pattern mapping
                let isPatternLetter = highlightMap[unitIndex] ?? false
                let baseColor: Color = isPatternLetter ? .blue : .black
                
                // Check if this position has internal hooks
                let hasInternalHook = hooks != nil && (
                    (unitIndex == 0 && !(hooks!.leftInternal.isEmpty)) ||
                    (unitIndex == wordUnits.count - 1 && !(hooks!.rightInternal.isEmpty))
                )
                
                if hasInternalHook {
                    // Internal hooks: same color but more translucent for subtle distinction
                    attributed[range].foregroundColor = baseColor.opacity(0.4)
                    attributed[range].font = .title3
                } else {
                    // Normal letters: regular styling
                    attributed[range].foregroundColor = baseColor
                    attributed[range].font = .title3
                }
            }
            charPosition += unit.count
        }
        
        return attributed
    }
    
    /// Create a map indicating which character positions belong to the pattern
    private func getPatternHighlightMap(word: String, pattern: String) -> [Int: Bool] {
        let normalizedPattern = SpanishUtils.normalize(pattern.uppercased())
        let normalizedWord = SpanishUtils.normalize(word.uppercased())
        
        // Convert to regex pattern for finding the first match
        let regexPattern = normalizedPattern
            .replacingOccurrences(of: ".", with: "[A-ZÑÇ]")
            .replacingOccurrences(of: "*", with: "[A-ZÑÇ]*")
        
        var highlightMap: [Int: Bool] = [:]
        
        // Try to find the pattern in the word
        if let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$"),
           let match = regex.firstMatch(in: normalizedWord, range: NSRange(location: 0, length: normalizedWord.count)) {
            
            // Found a match, now map which positions are pattern vs fill
            highlightMap = mapPatternPositions(
                word: normalizedWord,
                pattern: normalizedPattern,
                wordUnits: SpanishUtils.splitIntoSpanishUnits(word)
            )
        }
        
        return highlightMap
    }
    
    /// Map each position in the word to whether it's part of the pattern or fill
    private func mapPatternPositions(word: String, pattern: String, wordUnits: [String]) -> [Int: Bool] {
        var result: [Int: Bool] = [:]
        
        let patternChars = Array(pattern)
        let wordChars = Array(word)
        
        var patternIndex = 0
        var wordIndex = 0
        var unitIndex = 0
        
        // Process pattern character by character
        while patternIndex < patternChars.count && unitIndex < wordUnits.count {
            let patternChar = patternChars[patternIndex]
            
            if patternChar == "*" {
                // Handle leading/trailing/middle wildcards
                if patternIndex == 0 {
                    // Leading wildcard: consume until we find the next pattern segment
                    let nextPatternSegment = extractNextFixedSegment(from: pattern, startingAt: patternIndex + 1)
                    if let nextSegment = nextPatternSegment {
                        // Find where this segment appears in the word
                        let segmentStart = findSegmentInWord(segment: nextSegment, in: word, from: wordIndex)
                        if let start = segmentStart {
                            // Mark all units before the segment as fill (false)
                            while wordIndex < start {
                                result[unitIndex] = false
                                wordIndex += 1
                                unitIndex += 1
                            }
                        }
                    } else {
                        // Rest of word is fill
                        while unitIndex < wordUnits.count {
                            result[unitIndex] = false
                            unitIndex += 1
                        }
                        break
                    }
                } else if patternIndex == patternChars.count - 1 {
                    // Trailing wildcard: rest of word is fill
                    while unitIndex < wordUnits.count {
                        result[unitIndex] = false
                        unitIndex += 1
                    }
                    break
                } else {
                    // Middle wildcard: find next fixed segment
                    let nextPatternSegment = extractNextFixedSegment(from: pattern, startingAt: patternIndex + 1)
                    if let nextSegment = nextPatternSegment {
                        let segmentStart = findSegmentInWord(segment: nextSegment, in: word, from: wordIndex)
                        if let start = segmentStart {
                            // Mark fill until segment
                            while wordIndex < start {
                                result[unitIndex] = false
                                wordIndex += 1
                                unitIndex += 1
                            }
                        }
                    }
                }
                patternIndex += 1
            } else if patternChar == "." {
                // Single wildcard: mark as fill
                result[unitIndex] = false
                wordIndex += 1
                unitIndex += 1
                patternIndex += 1
            } else if patternChar == "@" || patternChar == "&" {
                // Pattern symbols (@ for vowels, & for consonants): mark as pattern
                result[unitIndex] = true
                wordIndex += 1
                unitIndex += 1
                patternIndex += 1
            } else {
                // Fixed character: mark as pattern
                result[unitIndex] = true
                wordIndex += 1
                unitIndex += 1
                patternIndex += 1
            }
        }
        
        return result
    }
    
    /// Extract the next continuous fixed segment from pattern
    private func extractNextFixedSegment(from pattern: String, startingAt index: Int) -> String? {
        let patternChars = Array(pattern)
        var segment = ""
        var i = index
        
        while i < patternChars.count {
            let char = patternChars[i]
            if char == "*" || char == "." {
                break
            }
            // @ and & are part of pattern segments, not breaks
            segment += String(char)
            i += 1
        }
        
        return segment.isEmpty ? nil : segment
    }
    
    /// Find where a segment appears in the word starting from a given position
    private func findSegmentInWord(segment: String, in word: String, from startIndex: Int) -> Int? {
        let wordChars = Array(word)
        let segmentChars = Array(segment)
        
        for i in startIndex...(wordChars.count - segmentChars.count) {
            var match = true
            for j in 0..<segmentChars.count {
                if wordChars[i + j] != segmentChars[j] {
                    match = false
                    break
                }
            }
            if match {
                return i
            }
        }
        return nil
    }
    
    // MARK: - Subanagrams Generation
    
    private func generateSubanagrams() {
        let cleanedQuery = searchModel.query.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            subanagramsByLength = [:]
            subanagramsWithHooks = [:]
            return
        }
        
        // Normalize input using SpanishUtils
        let normalizedInput = SpanishUtils.normalize(cleanedQuery).uppercased()
        let inputChars = Array(normalizedInput)
        
        var resultsByLength: [Int: Set<String>] = [:]
        
        // Generate all possible combinations from length 2 to input length - 1
        for length in 2..<inputChars.count {
            let combinations = generateCombinations(from: inputChars, length: length)
            
            for combination in combinations {
                let combinationString = String(combination)
                let alphagram = SpanishUtils.generateAlphagram(combinationString)
                
                // Find words matching this alphagram
                let matchingWords = searchModel.findAnagramsByAlphagram(alphagram)
                
                for word in matchingWords {
                    let denormalizedWord = SpanishUtils.denormalize(word)
                    resultsByLength[length, default: Set()].insert(denormalizedWord)
                }
            }
        }
        
        // Convert Sets to sorted Arrays and generate hooks
        var finalResults: [Int: [String]] = [:]
        var finalResultsWithHooks: [Int: [(String, WordHooks?)]] = [:]
        
        for (length, wordSet) in resultsByLength {
            let sortedWords = Array(wordSet).sorted { SpanishUtils.compareSpanishOrder($0, $1) }
            finalResults[length] = sortedWords
            
            // Generate hooks for this length group
            let normalizedWords = sortedWords.map { SpanishUtils.normalize($0) }
            let hooksData = searchModel.getHooks(for: normalizedWords)
            
            finalResultsWithHooks[length] = sortedWords.map { word in
                let normalizedWord = SpanishUtils.normalize(word)
                return (word, hooksData[normalizedWord])
            }
        }
        
        subanagramsByLength = finalResults
        subanagramsWithHooks = finalResultsWithHooks
        
        // Initialize expansion state for all lengths
        for length in finalResults.keys {
            if subanagramExpansionState[length] == nil {
                subanagramExpansionState[length] = true
            }
        }
    }
    
    private func generateCombinations(from chars: [Character], length: Int) -> Set<[Character]> {
        var results = Set<[Character]>()
        
        func backtrack(current: [Character], remaining: [Character]) {
            if current.count == length {
                results.insert(current.sorted())
                return
            }
            
            for i in 0..<remaining.count {
                var newCurrent = current
                newCurrent.append(remaining[i])
                
                var newRemaining = remaining
                newRemaining.remove(at: i)
                
                backtrack(current: newCurrent, remaining: newRemaining)
            }
        }
        
        backtrack(current: [], remaining: chars)
        return results
    }
    
    // MARK: - Sorting Functions
    
    /// Returns wildcard results sorted alphabetically by wildcard letters
    private func getSortedWildcardResults() -> [WildcardResult] {
        return searchModel.searchResult.wildcardResults.sorted { result1, result2 in
            // Sort by wildcard letters (concatenated)
            let letters1 = result1.wildcardLetters.map { String($0) }.joined()
            let letters2 = result2.wildcardLetters.map { String($0) }.joined()
            return letters1 < letters2
        }
    }
    
    /// Returns extra letter results sorted alphabetically by extra letter
    private func getSortedExtraLetterResults() -> [ExtraLetterResult] {
        return searchModel.searchResult.extraLetterResults.sorted { result1, result2 in
            // Sort by extra letter
            return String(result1.extraLetter) < String(result2.extraLetter)
        }
    }
    
    /// Highlights letters that exceed the original rack using simplified logic
    private func highlightExtraLetter(word: String, extraLetter: Character, hooks: WordHooks? = nil, showHooks: Bool = false, originalRack: String) -> AttributedString {
        var attributed = AttributedString(word)
        
        // Use Spanish units for proper dígrafo handling
        let originalRackUnits = SpanishUtils.splitIntoSpanishUnits(originalRack)
        let normalizedOriginalRack = originalRackUnits.map { SpanishUtils.normalize($0).uppercased() }
        
        // Count available units in original rack
        var availableUnits: [String: Int] = [:]
        for unit in normalizedOriginalRack {
            availableUnits[unit, default: 0] += 1
        }
        
        // Count used units as we process the word
        var usedUnits: [String: Int] = [:]
        
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(word)
        var charPosition = 0
        
        for (unitIndex, unit) in wordUnits.enumerated() {
            let normalizedUnit = SpanishUtils.normalize(unit).uppercased()
            usedUnits[normalizedUnit, default: 0] += 1
            let availableCount = availableUnits[normalizedUnit, default: 0]
            
            // If this usage exceeds what was available in original rack, highlight it
            if usedUnits[normalizedUnit, default: 0] > availableCount {
                if let startPos = word.index(word.startIndex, offsetBy: charPosition, limitedBy: word.endIndex),
                   let endPos = word.index(startPos, offsetBy: unit.count, limitedBy: word.endIndex),
                   let startIdx = AttributedString.Index(startPos, within: attributed),
                   let endIdx = AttributedString.Index(endPos, within: attributed) {
                    
                    let range = startIdx..<endIdx
                    
                    // Check if this position coincides with internal hooks AND hooks are being shown
                    let isInternalHook = showHooks && hooks != nil && (
                        (unitIndex == 0 && !(hooks!.leftInternal.isEmpty)) ||
                        (unitIndex == wordUnits.count - 1 && !(hooks!.rightInternal.isEmpty))
                    )
                    
                    // Use dark red (pardo) if coincides with internal hook AND hooks are visible, regular red otherwise
                    attributed[range].foregroundColor = isInternalHook ? 
                        Color(.sRGB, red: 0.6, green: 0.2, blue: 0.2, opacity: 1.0) : .red
                    attributed[range].font = .title3.bold()
                }
            }
            charPosition += unit.count
        }
        
        return attributed
    }

    /// Builds a row showing external hooks and inline internal hooks with encapsulated hooks
    private func hookRowView(word: String, hooks: WordHooks?, extraLetter: Character? = nil, wildcardPositions: [Int] = []) -> some View {
        let wordLength = word.count
        
        // Count actual hooks for dynamic sizing
        let leftHookCount = SpanishUtils.splitIntoSpanishUnits(SpanishUtils.denormalize(hooks?.leftExternal ?? "")).count
        let rightHookCount = SpanishUtils.splitIntoSpanishUnits(SpanishUtils.denormalize(hooks?.rightExternal ?? "")).count
        
        // Pre-calculate dynamic height based on estimated rows
        let estimatedMaxRows = max(
            calculateRows(hookCount: leftHookCount, availableWidth: 120), // Estimate
            calculateRows(hookCount: rightHookCount, availableWidth: 120)
        )
        let dynamicHeight: CGFloat = max(36, CGFloat(estimatedMaxRows) * 26 + 10) // Minimized for maximum space efficiency
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width - 24 // Account for padding
            
            // DYNAMIC sizing based on actual hook count and word length
            let maxHooksPerSide = max(leftHookCount, rightHookCount)
            
            let hookColumnWidth: CGFloat = {
                // Calculate needed width based on actual hooks (always 4 per row)
                let hooksPerRow = maxHooksPerSide <= 2 ? maxHooksPerSide : 4
                // Rows calculation not needed for width, only for height calculation elsewhere
                let baseWidth = CGFloat(hooksPerRow) * 28 + CGFloat(max(0, hooksPerRow - 1)) * 2 // hooks + spacing
                
                // Minimum width for visual consistency, maximum for screen limits
                return max(baseWidth, 60).clamped(to: 40...140)
            }()
            
            let wordColumnWidth: CGFloat = {
                // Dynamic word width based on length and available space
                let idealWordWidth = max(CGFloat(wordLength) * 12, 60) // Base calculation
                let remainingWidth = availableWidth - (2 * hookColumnWidth) - 8
                
                // Smart allocation: give more space to longer words, less to shorter ones
                if wordLength <= 3 {
                    return max(60, min(idealWordWidth, remainingWidth * 0.3)) // Short words get less space
                } else if wordLength <= 6 {
                    return max(80, min(idealWordWidth, remainingWidth * 0.5)) // Medium words get balanced space
                } else {
                    return max(100, min(idealWordWidth, remainingWidth * 0.7)) // Long words get priority
                }
            }()
            
            let totalWidth = hookColumnWidth + wordColumnWidth + hookColumnWidth + 8 // Include spacing
            
            HStack(alignment: .center, spacing: 4) {
                // Left external hooks
                flexibleHooksView(
                    hooks: hooks?.leftExternal ?? "",
                    alignment: .trailing,
                    wordLength: wordLength,
                    availableWidth: hookColumnWidth
                )
                .frame(width: hookColumnWidth, alignment: .trailing)
                
                // Center: word - adaptive sizing for long words
                highlightedWord(word: word, hooks: hooks, originalRack: getOriginalRackForHookRow(extraLetter: extraLetter, wildcardPositions: wildcardPositions))
                    .font(.title3)
                    .fontWeight(.bold)
                    .frame(width: wordColumnWidth, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5) // Allow shrinking for very long words
                
                // Right external hooks
                flexibleHooksView(
                    hooks: hooks?.rightExternal ?? "",
                    alignment: .leading,
                    wordLength: wordLength,
                    availableWidth: hookColumnWidth
                )
                .frame(width: hookColumnWidth, alignment: .leading)
            }
            .frame(width: totalWidth)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(height: dynamicHeight) // Dynamic height based on hook rows
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            openRAEDefinition(for: word)
        }
    }
    
    /// Creates a flexible wrap layout for hooks with proper alignment  
    private func flexibleHooksView(hooks: String, alignment: HorizontalAlignment, wordLength: Int = 5, availableWidth: CGFloat = 120) -> some View {
        let denorm = SpanishUtils.denormalize(hooks)
        let units = SpanishUtils.splitIntoSpanishUnits(denorm)
        let uniqueUnits = Array(Set(units)).sorted()
        
        // INTELLIGENT hooks per row based on available width AND hook count
        let hooksPerRow: Int = {
            let hookCount = uniqueUnits.count
            if hookCount == 0 { return 0 }
            
            // Hook width based on square size + spacing (for reference only)
            // let estimatedHookWidth: CGFloat = 28 // 26px square + 2px spacing
            // let maxHooksInWidth = Int(availableWidth / estimatedHookWidth) // Not used with fixed 4-per-row
            
            // FORCE exactly 4 hooks per row (except for 1-2 hooks)
            switch hookCount {
            case 0: return 0
            case 1...2: return hookCount // Single row for 1-2 hooks
            default: return 4 // ALWAYS 4 hooks per row for 3+ hooks
            }
        }()
        
        return Group {
            if uniqueUnits.isEmpty {
                // Empty placeholder to maintain spacing
                Spacer()
            } else if uniqueUnits.count <= 3 {
                // Single row for very few hooks - always align towards word
                HStack(spacing: 2) {
                    if alignment == .trailing { 
                        Spacer() // Push hooks to the right (towards word)
                    }
                    
                    ForEach(uniqueUnits, id: \.self) { unit in
                        hookUnitView(unit: unit)
                    }
                    
                    if alignment == .leading { 
                        Spacer() // Push hooks to the left (towards word)
                    }
                }
            } else {
                // Multi-row wrap with dynamic hooks per row
                VStack(alignment: alignment, spacing: 1) {
                    let chunkedUnits = uniqueUnits.chunked(into: hooksPerRow)
                    ForEach(Array(chunkedUnits.enumerated()), id: \.offset) { _, chunk in
                        HStack(spacing: 2) {
                            if alignment == .trailing { 
                                Spacer() // Push hooks to the right (towards word)
                            }
                            
                            ForEach(chunk, id: \.self) { unit in
                                hookUnitView(unit: unit)
                            }
                            
                            if alignment == .leading { 
                                Spacer() // Push hooks to the left (towards word)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Individual hook unit view - perfect square to fit "ch"
    private func hookUnitView(unit: String) -> some View {
        Text(unit.lowercased())
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 26, height: 26) // Perfect square for "ch"
            .background(Color.secondary.opacity(0.8))
            .cornerRadius(4)
    }

    /// Highlights any letter that exceeds what's available in the original rack (wildcards/extra letters)
    private func highlightedWord(word: String, hooks: WordHooks?, originalRack: String) -> Text {
        // Use Spanish units for proper dígrafo handling
        let originalRackUnits = SpanishUtils.splitIntoSpanishUnits(originalRack)
        let normalizedOriginalRack = originalRackUnits.map { SpanishUtils.normalize($0).uppercased() }
        
        // Count available units in original rack
        var availableUnits: [String: Int] = [:]
        for unit in normalizedOriginalRack {
            availableUnits[unit, default: 0] += 1
        }
        
        // Count used units as we process the word
        var usedUnits: [String: Int] = [:]
        
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(word)
        var text = Text("")
        
        for (unitIndex, unit) in wordUnits.enumerated() {
            var color: Color = .primary
            var isBold = false
            
            // Normalize unit for comparison
            let normalizedUnit = SpanishUtils.normalize(unit).uppercased()
            
            // Check if this unit is part of internal hooks
            if let h = hooks,
               ((unitIndex == 0 && !h.leftInternal.isEmpty) || (unitIndex == wordUnits.count - 1 && !h.rightInternal.isEmpty)) {
                // Internal hooks shown in gray
                color = .secondary
            }
            
            // Count this unit usage
            usedUnits[normalizedUnit, default: 0] += 1
            let availableCount = availableUnits[normalizedUnit, default: 0]
            
            // If this usage exceeds what was available in original rack, highlight it (wildcard/extra letter)
            if usedUnits[normalizedUnit, default: 0] > availableCount {
                color = .red
                isBold = true
                
                // Special case: if coincides with internal hook, use dark red (pardo)
                if let h = hooks,
                   ((unitIndex == 0 && !h.leftInternal.isEmpty) || (unitIndex == wordUnits.count - 1 && !h.rightInternal.isEmpty)) {
                    color = Color(.sRGB, red: 0.6, green: 0.2, blue: 0.2, opacity: 1.0) // Dark red/pardo
                }
            }
            
            let unitText = isBold ? Text(unit).bold() : Text(unit)
            text = text + unitText.foregroundColor(color)
        }
        return text.font(.title3).fontWeight(.medium)
    }
    
    /// Helper to find the unit index for a character index
    private func findCharUnitIndex(charIndex: Int, in word: String, units: [String]) -> Int {
        var currentCharIndex = 0
        for (unitIndex, unit) in units.enumerated() {
            if charIndex >= currentCharIndex && charIndex < currentCharIndex + unit.count {
                return unitIndex
            }
            currentCharIndex += unit.count
        }
        return -1 // Not found
    }
    
    /// Helper function to calculate number of rows needed for hooks
    private func calculateRows(hookCount: Int, availableWidth: CGFloat) -> Int {
        if hookCount == 0 { return 1 } // Minimum 1 row for spacing
        
        // Width calculation not needed for fixed 4-per-row layout
        // let estimatedHookWidth: CGFloat = 28 // 26px square + 2px spacing  
        // let maxHooksInWidth = Int(availableWidth / estimatedHookWidth)
        
        let hooksPerRow: Int = {
            switch hookCount {
            case 0: return 0
            case 1...2: return hookCount
            default: return 4 // ALWAYS 4 hooks per row for 3+ hooks
            }
        }()
        
        return max(1, Int(ceil(Double(hookCount) / Double(hooksPerRow))))
    }
    
    /// Helper to get original rack for hook row highlighting
    private func getOriginalRackForHookRow(extraLetter: Character? = nil, wildcardPositions: [Int] = []) -> String {
        // Extract original rack from current search query (remove wildcards)
        let cleanedQuery = searchModel.query.replacingOccurrences(of: "?", with: "")
        return cleanedQuery
    }
    
    // MARK: - Hamburger Menu
    
    @ViewBuilder
    private var hamburgerMenuSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Menu Options
                VStack(spacing: 16) {
                    // Hooks Toggle
                    HStack {
                        Image(systemName: showHooks ? "eye.fill" : "eye")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mostrar ganchos")
                                .font(.headline)
                            Text("Ver extensiones de palabras")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $showHooks)
                            .labelsHidden()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Copy Words Button
                    Button {
                        copyAllWords()
                        showHamburgerMenu = false
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Copiar palabras")
                                    .font(.headline)
                                Text("Todas las palabras en orden alfabético")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
                
                // Help Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Ayuda de Sintaxis")
                            .font(.headline)
                        Spacer()
                    }
                    
                    helpContent
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Menú")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") {
                        showHamburgerMenu = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Anagramas
            VStack(alignment: .leading, spacing: 4) {
                Text("Anagramas")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("LETRAS? - Con comodín")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
                Text("Ejemplo: JERAS?")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Patrones
            VStack(alignment: .leading, spacing: 4) {
                Text("Patrones")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("M...N,RACK - Patrón con rack")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
                Text("Ejemplo: J.R.S,AEIO")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("+ABC - Debe contener")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
                Text("-XYZ - No debe contener")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
                Text("*:5 - Longitud específica")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            // Validador
            VStack(alignment: .leading, spacing: 4) {
                Text("Validador")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("PALABRA ESPACIOS - Validar múltiples")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .foregroundColor(.blue)
                Text("Ejemplo: CASA PERRO GATO")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Copy Functionality
    
    private func copyAllWords() {
        var allWords: [String] = []
        
        // Collect all visible words based on current search results
        switch searchModel.searchResult.mode {
        case .validator:
            allWords = searchModel.searchResult.validationResults.map { $0.word }
            
        case .anagram:
            // Add anagram results
            allWords.append(contentsOf: searchModel.searchResult.anagramResults.map { $0.word })
            
            // Add wildcard results
            allWords.append(contentsOf: searchModel.searchResult.wildcardResults.map { $0.word })
            
            // Add extra letter results
            allWords.append(contentsOf: searchModel.searchResult.extraLetterResults.map { $0.word })
            
            // Add subanagram results if showing subanagrams
            if showSubanagrams {
                // Relevant wildcard results
                allWords.append(contentsOf: searchModel.searchResult.relevantWildcardResults.map { $0.word })
                
                // No wildcard subanagrams
                allWords.append(contentsOf: searchModel.searchResult.subanagramsNoWildcard.map { $0.word })
                
                // Other wildcard subanagrams
                allWords.append(contentsOf: searchModel.searchResult.subanagramsWithWildcard.map { $0.word })
            }
            
        case .pattern:
            if let patternResult = searchModel.searchResult.patternSearchResult {
                for (_, words) in patternResult.wordsByLength {
                    allWords.append(contentsOf: words)
                }
            }
        }
        
        // Remove duplicates and sort alphabetically using Spanish order
        let uniqueWords = Array(Set(allWords))
        let sortedWords = uniqueWords.sorted { SpanishUtils.compareSpanishOrder($0, $1) }
        
        // Convert to uppercase and denormalize digraphs
        let finalWords = sortedWords.map { word in
            SpanishUtils.denormalize(word).uppercased()
        }
        
        // Create final string with one word per line
        let copyText = finalWords.joined(separator: "\n")
        
        // Copy to clipboard
        UIPasteboard.general.string = copyText
        
        // Could add a toast notification here if desired
        print("📋 Copied \(finalWords.count) words to clipboard")
    }
    
    // MARK: - RAE Dictionary Navigation
    
    /// Opens RAE DLE definition for the given word using in-app Safari
    private func openRAEDefinition(for word: String) {
        let cleanWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encodedWord = cleanWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dle.rae.es/\(encodedWord)") else {
            return
        }
        
        // Create SFSafariViewController with restricted navigation and reader mode
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        config.barCollapsingEnabled = true
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        
        // Configure minimal UI
        safariVC.preferredBarTintColor = UIColor.systemBackground
        safariVC.preferredControlTintColor = UIColor.systemBlue
        safariVC.dismissButtonStyle = .done
        
        // Present modally
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        // Find the top-most presented view controller
        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        topViewController.present(safariVC, animated: true, completion: nil)
    }
    
    // MARK: - Pattern Analysis Helpers
    
    /// Determines if the current pattern has a fixed length implicitly
    private func hasFixedLength() -> Bool {
        guard let patternResult = searchModel.searchResult.patternSearchResult else {
            return false
        }
        
        // Only disable toggle if there's an explicit length restriction in the query (e.g., ":7")
        // Don't disable based on result counts - that's incorrect for open searches like "*ABC"
        return patternResult.hasExplicitLengthRestriction
    }
    
    // MARK: - Performance Toast"
    
    @ViewBuilder
    private var performanceToastView: some View {
        if searchModel.showPerformanceToast {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(searchModel.performanceMessage)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.black.opacity(0.8))
                        )
                    Spacer()
                }
                .padding(.bottom, 50) // Position above tab bar
            }
        }
    }
    
}

// MARK: - Preview

struct UnifiedSearchView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedSearchView()
    }
}