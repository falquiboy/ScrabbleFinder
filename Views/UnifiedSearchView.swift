import SwiftUI

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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // Fixed compact title
                Text("+Léxico")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                
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
                                // Clear button with larger touch area
                                if !searchModel.query.isEmpty {
                                    Button {
                                        searchModel.clearSearch()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
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
                    // Hooks toggle for anagram & pattern modes (validator hides)
                    if searchModel.searchResult.mode != .validator {
                        HStack {
                            Toggle("Mostrar ganchos", isOn: $showHooks)
                        }
                        .padding(.horizontal)
                    }
                    // Display hook‑enhanced view or legacy layout
                    if showHooks && searchModel.searchResult.mode != .validator {
                        hooksResultsView
                    } else {
                        resultsView
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .navigationBarHidden(true)
            .onTapGesture {
                hideKeyboard()
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
        if !searchModel.searchResult.anagramResults.isEmpty || !searchModel.searchResult.wildcardResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                
                // Result Count
                Text(searchModel.resultCount)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                // Results List
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        
                        // Regular anagram results with hooks
                        ForEach(searchModel.searchResult.anagramResults, id: \.word) { result in
                            VStack(spacing: 2) {
                                Text(formatWordWithHooks(result))
                                    .font(.title3)
                                    .fontWeight(.medium)
                                
                                if let hooks = result.hooks, hooks.hasInternalHooks {
                                    Text(hooks.internalDisplay)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Wildcard results with highlighted wildcards and hooks
                        ForEach(searchModel.searchResult.wildcardResults, id: \.word) { result in
                            VStack(spacing: 2) {
                                Text(highlightWildcards(in: result))
                                    .font(.title3)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 8) {
                                    if let hooks = result.hooks, hooks.hasExternalHooks {
                                        Text(hooks.externalDisplay)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    if let hooks = result.hooks, hooks.hasInternalHooks {
                                        Text(hooks.internalDisplay)
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Pattern Results (Placeholder)
    
    @ViewBuilder
    private var patternResultsView: some View {
        if !searchModel.searchResult.patternResults.isEmpty {
            VStack {
                Text(searchModel.resultCount)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Funcionalidad de patrones próximamente")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        isInputFocused = false
        hideKeyboard()
        searchModel.performSearch()
    }
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    /// Creates an AttributedString with wildcard characters highlighted in red
    private func highlightWildcards(in result: WildcardResult) -> AttributedString {
        var attributed = AttributedString(result.word)
        
        // Split word into Spanish alphabet units (handling digraphs)
        let wordUnits = SpanishUtils.splitIntoSpanishUnits(result.word)
        
        // Highlight wildcard positions
        var charPosition = 0
        for (unitIndex, unit) in wordUnits.enumerated() {
            if result.wildcardPositions.contains(unitIndex) {
                // Calculate the range for this unit in the attributed string
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
            LazyVStack(alignment: .leading, spacing: 8) {
                // Regular anagrams
                ForEach(searchModel.searchResult.anagramResults, id: \.word) { result in
                    hookRowView(word: result.word, hooks: result.hooks)
                }
                // Wildcard results
                ForEach(searchModel.searchResult.wildcardResults, id: \.word) { result in
                    hookRowView(word: result.word, hooks: result.hooks)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Builds a row showing external hooks and inline internal hooks with encapsulated hooks
    private func hookRowView(word: String, hooks: WordHooks?) -> some View {
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
                highlightedWord(word: word, hooks: hooks)
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

    /// Highlights the first/last character for internal hooks inline
    private func highlightedWord(word: String, hooks: WordHooks?) -> Text {
        let chars = Array(word)
        var text = Text("")
        for (idx, char) in chars.enumerated() {
            let str = String(char)
            if let h = hooks,
               ((idx == 0 && !h.leftInternal.isEmpty) || (idx == chars.count - 1 && !h.rightInternal.isEmpty)) {
                // Internal hooks shown in gray, not italic
                text = text + Text(str).foregroundColor(.secondary)
            } else {
                text = text + Text(str)
            }
        }
        return text.font(.title3).fontWeight(.medium)
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
}

// MARK: - Preview

struct UnifiedSearchView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedSearchView()
    }
}