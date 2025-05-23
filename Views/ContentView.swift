import SwiftUI
import SafariServices
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = AnagramViewModel()
    @State private var selectedItem: SafariItem?
    @FocusState private var isQueryFocused: Bool
    @State private var hasSearched: Bool = false

    /// Copies all currently displayed words (denormalized) to the clipboard, one per line.
    private func copyAllWords() {
        var wordsToCopy: [String] = []
        if !viewModel.wildcardResults.isEmpty {
            wordsToCopy = viewModel.wildcardResults.map { $0.word }
        } else if viewModel.enableShorterWords {
            wordsToCopy = viewModel.shorterWordsResults
        } else {
            wordsToCopy.append(contentsOf: viewModel.results)
            wordsToCopy.append(contentsOf: viewModel.extraLetterResults.map { $0.word })
        }
        
        #if canImport(UIKit)
        UIPasteboard.general.string = wordsToCopy.joined(separator: "\n")
        #endif
    }

    var body: some View {
        VStack {
            HStack {
                TextField("INGRESA LETRAS", text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0.uppercased() }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .focused($isQueryFocused)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.searchAnagrams()
                }
                .overlay(
                    HStack {
                        Spacer()
                        if !viewModel.query.isEmpty {
                            Button {
                                viewModel.query = ""
                                viewModel.query = ""
                                viewModel.results.removeAll()
                                viewModel.extraLetterResults.removeAll()
                                viewModel.wildcardResults.removeAll()
                                viewModel.shorterWordsResults.removeAll() // Clear shorter words results
                                hasSearched = false
                                // viewModel.enableShorterWords = false // Optionally reset toggle
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                )

                Button {
                    viewModel.searchAnagrams()
                    hasSearched = true
                    isQueryFocused = false
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                }
                Button {
                    copyAllWords()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                }
                .disabled(shouldDisableCopyButton())
            }
            .padding(.horizontal)
            .padding(.top)

            Toggle("Buscar palabras más cortas", isOn: $viewModel.enableShorterWords)
                .padding(.horizontal)
                .disabled(!viewModel.wildcardResults.isEmpty) // Disable toggle if wildcard results are shown

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !viewModel.wildcardResults.isEmpty {
                        // Section for Wildcard Results
                        Text("\(viewModel.wildcardResults.count) palabras con comodines")
                            .font(.title3)
                            .bold()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(viewModel.wildcardResults.sorted(by: { spanishScrabbleOrder($0.word, $1.word) })) { entry in
                                let attributed = highlightWildcards(in: entry.word, wildcards: entry.wildcardLetters)
                                Text(attributed)
                                    .onTapGesture {
                                        if let url = URL(string: "https://dle.rae.es/\(entry.word)") {
                                            selectedItem = SafariItem(url)
                                        }
                                    }
                                    .padding(4)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            }
                        }
                        // No specific "0 wildcard results" message typically, as this section only shows if results exist.
                        // ViewModel already ensures wildcardResults is populated only if matches are found.
                    } else { // No wildcards
                        if viewModel.enableShorterWords {
                            // Section for Shorter Words Results - Grouped
                            if !viewModel.groupedShorterWords.isEmpty {
                                // Overall count for shorter words
                                Text("Total: \(viewModel.shorterWordsResults.count) palabras más cortas")
                                    .font(.title3) // Keep title3 for main header
                                    .bold()
                                    .padding(.bottom, 2) // Minor spacing adjustment

                                ForEach(viewModel.groupedShorterWords) { group in
                                    DisclosureGroup(
                                        content: {
                                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                                ForEach(group.words, id: \.self) { word in
                                                    Text(word)
                                                        .onTapGesture {
                                                            if let url = URL(string: "https://dle.rae.es/\(word)") {
                                                                selectedItem = SafariItem(url)
                                                            }
                                                        }
                                                        .padding(4)
                                                        .frame(maxWidth: .infinity)
                                                        .background(Color(.systemGray6))
                                                        .cornerRadius(6)
                                                }
                                            }
                                            .padding(.top, 8) // Padding inside disclosure group
                                        },
                                        label: {
                                            Text("Palabras de \(group.length) letras (\(group.words.count) palabras)")
                                                .font(.headline) // Headline for group titles
                                                .foregroundColor(.primary) // Ensure label text is clearly visible
                                        }
                                    )
                                }
                            } else if hasSearched { // This implies groupedShorterWords is empty
                                Text("0 palabras más cortas encontradas")
                                    .font(.headline)
                                    .padding(.top)
                            }
                        } else {
                            // Section for Exact Matches
                            if !viewModel.results.isEmpty {
                                Text("\(viewModel.results.count) palabras con todas las fichas")
                                    .font(.title3)
                                    .bold()
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(viewModel.results.sorted(by: spanishScrabbleOrder), id: \.self) { word in
                                        Text(word)
                                            .onTapGesture {
                                                if let url = URL(string: "https://dle.rae.es/\(word)") {
                                                    selectedItem = SafariItem(url)
                                                }
                                            }
                                            .padding(4)
                                            .frame(maxWidth: .infinity)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(6)
                                    }
                                }
                            } else if hasSearched {
                                 Text("0 palabras con todas las fichas")
                                    .font(.title3) // Kept .title3 as per original for this message
                                    .bold()
                                    .padding(.top)
                            }

                            // Section for Extra Letter Results
                            if !viewModel.extraLetterResults.isEmpty {
                                Text("\(viewModel.extraLetterResults.count) palabras con una ficha adicional")
                                    .font(.title3)
                                    .bold()
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(viewModel.extraLetterResults.sorted {
                                        spanishScrabbleOrderWithKey($0.word, $1.word, keyA: $0.extraLetter, keyB: $1.extraLetter)
                                    }) { entry in
                                        let attributed = highlightExtraLetter(in: entry.word, extra: entry.extraLetter)
                                        Text(attributed)
                                            .onTapGesture {
                                                if let url = URL(string: "https://dle.rae.es/\(entry.word)") {
                                                    selectedItem = SafariItem(url)
                                                }
                                            }
                                            .padding(4)
                                            .frame(maxWidth: .infinity)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            // No "0 extra letter results" message was in original; not adding one unless specified.
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom) // Adjusted padding to .bottom only, as .horizontal and .top are on the HStack
        .sheet(item: $selectedItem) { item in
            SafariView(url: item.url)
                .presentationDetents([.medium, .large])
        }
    }

    private func shouldDisableCopyButton() -> Bool {
        if !viewModel.wildcardResults.isEmpty {
            // This case implies wildcardResults is not empty, so copy shouldn't be disabled.
            // However, if somehow it could be empty, this would catch it.
            return viewModel.wildcardResults.isEmpty
        } else if viewModel.enableShorterWords {
            return viewModel.shorterWordsResults.isEmpty
        } else {
            return viewModel.results.isEmpty && viewModel.extraLetterResults.isEmpty
        }
    }
}

func highlightExtraLetter(in word: String, extra: Character) -> AttributedString {
    var attributed = AttributedString(word)
    if let digraph = internalToDigraphs[extra] {
        // Extra letter is a digraph; highlight the full string
        if let range = attributed.range(of: digraph, options: [.caseInsensitive]) {
            attributed[range].foregroundColor = .red
            attributed[range].font = .body.bold()
        }
    } else {
        // Normal single character
        if let range = attributed.range(of: String(extra), options: [.caseInsensitive]) {
            attributed[range].foregroundColor = .red
            attributed[range].font = .body.bold()
        }
    }
    return attributed
}

func highlightWildcards(in word: String, wildcards: [Character]) -> AttributedString {
    var attributed = AttributedString(word)
    for letter in wildcards {
        let display = internalToDigraphs[letter] ?? String(letter)
        if let range = attributed.range(of: display, options: [.caseInsensitive]) {
            attributed[range].foregroundColor = .red
            attributed[range].font = .body.bold()
        }
    }
    return attributed
}

// Spanish Scrabble alphabet with digraphs
let spanishAlphabet: [String] = [
    "A", "B", "C", "CH", "D", "E", "F", "G", "H", "I", "J", "L", "LL",
    "M", "N", "Ñ", "O", "P", "Q", "R", "RR", "S", "T", "U", "V", "X", "Y", "Z"
]

let spanishOrder: [String: Int] = {
    var dict = [String: Int]()
    for (i, letter) in spanishAlphabet.enumerated() {
        dict[letter] = i
    }
    return dict
}()

func splitIntoUnits(_ word: String) -> [String] {
    var result: [String] = []
    let upper = word.uppercased()
    var i = upper.startIndex
    while i < upper.endIndex {
        let next = upper.index(after: i)
        if next < upper.endIndex {
            let pair = String(upper[i...upper.index(after: i)])
            if spanishOrder.keys.contains(pair) {
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

func spanishScrabbleOrder(_ a: String, _ b: String) -> Bool {
    let unitsA = splitIntoUnits(a)
    let unitsB = splitIntoUnits(b)
    let count = min(unitsA.count, unitsB.count)
    for i in 0..<count {
        let ua = unitsA[i]
        let ub = unitsB[i]
        let ia = spanishOrder[ua] ?? Int.max
        let ib = spanishOrder[ub] ?? Int.max
        if ia != ib {
            return ia < ib
        }
    }
    return unitsA.count < unitsB.count
}

func spanishScrabbleOrderWithKey(_ a: String, _ b: String, keyA: Character, keyB: Character) -> Bool {
    // Convert internal digraph letters to display digraphs if needed
    let da = internalToDigraphs[keyA] ?? String(keyA)
    let db = internalToDigraphs[keyB] ?? String(keyB)

    let orderA = spanishOrder[da] ?? Int.max
    let orderB = spanishOrder[db] ?? Int.max
    if orderA != orderB {
        return orderA < orderB
    }
    return spanishScrabbleOrder(a, b)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct SafariItem: Identifiable {
    let id: String
    let url: URL
    init(_ url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}
