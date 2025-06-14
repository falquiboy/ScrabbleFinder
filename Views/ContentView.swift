import SwiftUI
import SafariServices
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = AnagramViewModel()
    @State private var selectedItem: SafariItem?
    @FocusState private var isQueryFocused: Bool
    @State private var hasSearched: Bool = false
    @State private var expandedLengths: Set<Int> = []

    /// Copies all currently displayed words (denormalized) to the clipboard, one per line.
    private func copyAllWords() {
        let allWords = viewModel.results
            + viewModel.extraLetterResults.map { $0.word }
            + viewModel.wildcardResults.map { $0.word }
        #if canImport(UIKit)
        UIPasteboard.general.string = allWords.joined(separator: "\n")
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
                    hasSearched = true
                    isQueryFocused = false
                    #if canImport(UIKit)
                    UIApplication.shared.dismissKeyboard()
                    #endif
                }
                .onChange(of: viewModel.query) {
                    hasSearched = false
                    viewModel.showShorterWordsOnly = false
                    expandedLengths.removeAll()
                }
                .overlay(
                    HStack {
                        Spacer()
                        if !viewModel.query.isEmpty {
                            Button {
                                viewModel.query = ""
                                viewModel.results.removeAll()
                                viewModel.extraLetterResults.removeAll()
                                viewModel.wildcardResults.removeAll()
                                hasSearched = false
                                viewModel.showShorterWordsOnly = false
                                expandedLengths.removeAll()
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
                    #if canImport(UIKit)
                    UIApplication.shared.dismissKeyboard()
                    #endif
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
                .disabled(viewModel.results.isEmpty && viewModel.extraLetterResults.isEmpty && viewModel.wildcardResults.isEmpty)
            }
            .padding()

            HStack {
                Toggle("Mostrar palabras más cortas", isOn: $viewModel.showShorterWordsOnly)
                    .disabled(!hasSearched)
                    .onChange(of: viewModel.showShorterWordsOnly) { _, newValue in
                        if newValue {
                            viewModel.generateShorterWords()
                            expandedLengths = Set(viewModel.shorterWordResultsByLength.keys)
                        } else {
                            expandedLengths.removeAll()
                        }
                    }
                Spacer()
            }
            .padding(.horizontal)
            .onChange(of: viewModel.shorterWordResultsByLength) {
                expandedLengths = Set(viewModel.shorterWordResultsByLength.keys)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !viewModel.showShorterWordsOnly {
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
                        } else if hasSearched && viewModel.results.isEmpty {
                            Text("0 palabras con todas las fichas")
                                .font(.title3)
                                .bold()
                                .padding(.top)
                        }

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
                        if !viewModel.wildcardResults.isEmpty {
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
                        }
                    }
                    if viewModel.showShorterWordsOnly {
                        let allShorterWords = viewModel.shorterWordResultsByLength.values.flatMap { $0 }
                        Text("Palabras más cortas encontradas: \(allShorterWords.count)")
                            .font(.title3)
                            .bold()
                        ForEach(viewModel.shorterWordResultsByLength.keys.sorted(by: >), id: \.self) { length in
                            DisclosureGroup(
                                "\(length) letras (\(viewModel.shorterWordResultsByLength[length]?.count ?? 0))",
                                isExpanded: Binding(
                                    get: { expandedLengths.contains(length) },
                                    set: { newVal in
                                        if newVal {
                                            expandedLengths.insert(length)
                                        } else {
                                            expandedLengths.remove(length)
                                        }
                                    }
                                )
                            ) {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach((viewModel.shorterWordResultsByLength[length] ?? []).sorted(by: spanishScrabbleOrder), id: \.self) { word in
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
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        } // end VStack
        .padding()
        .onTapGesture {
            #if canImport(UIKit)
            UIApplication.shared.dismissKeyboard()
            #endif
        }
        .sheet(item: $selectedItem) { item in
            SafariView(url: item.url)
                .presentationDetents([.medium, .large])
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
