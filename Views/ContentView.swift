import SwiftUI
import SafariServices

struct ContentView: View {
    @StateObject private var viewModel = AnagramViewModel()
    @State private var selectedItem: SafariItem?
    @FocusState private var isQueryFocused: Bool
    @State private var hasSearched: Bool = false

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
                                viewModel.results.removeAll()
                                viewModel.extraLetterResults.removeAll()
                                viewModel.shorterWordsResults.removeAll() // Clear shorter words results too
                                hasSearched = false
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
            }
            .padding()

            Toggle("Mostrar palabras más cortas", isOn: Binding(
                get: { viewModel.showShorterWords },
                set: {
                    viewModel.showShorterWords = $0
                    if hasSearched {
                        viewModel.searchAnagrams()
                    }
                }
            ))
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Sections for Exact Matches and Extra Letter Matches - shown when showShorterWords is OFF
                    if !viewModel.showShorterWords {
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
                    }
                    
                    // Section for Shorter Words - shown when showShorterWords is ON
                    if viewModel.showShorterWords {
                        if !viewModel.shorterWordsResults.isEmpty {
                            Text("\(viewModel.shorterWordsResults.count) palabras más cortas")
                                .font(.title3)
                                .bold()
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(viewModel.shorterWordsResults, id: \.self) { word in // Already sorted by ViewModel
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
                        } else if hasSearched && viewModel.shorterWordsResults.isEmpty { // This condition is correct as per previous step
                             Text("0 palabras más cortas")
                                .font(.title3)
                                .bold()
                                .padding(.top)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
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
