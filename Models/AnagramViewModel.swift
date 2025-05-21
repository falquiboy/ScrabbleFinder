import Foundation
import TrieKit

struct ExtraLetterWord: Identifiable {
    let id = UUID()
    let word: String
    let extraLetter: Character
}

/// ViewModel for fetching anagrams from the bundled SQLite database.
final class AnagramViewModel: ObservableObject {
    // MARK: - Published properties for SwiftUI
    @Published var query: String = ""
    @Published var results: [String] = []
    @Published var extraLetterResults: [ExtraLetterWord] = []
    
    // MARK: - Private Trie root
    private let trieRoot: TrieNode

    // MARK: - Initialization
    init() {
        // Carga el trie.bin desde el bundle
        guard let url = Bundle.main.url(forResource: "trie", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            fatalError("❌ No se encontró trie.bin en el bundle")
        }
        let decoder = PropertyListDecoder()
        do {
            trieRoot = try decoder.decode(TrieNode.self, from: data)
        } catch {
            fatalError("❌ Error decodificando trie.bin: \(error)")
        }
    }

    // MARK: - Public search method
    /// Normalize input, filter by length + alphagram, then denormalize results.
    func searchAnagrams() {
        results.removeAll()
        extraLetterResults.removeAll()

        // 1) Limpia y normaliza la entrada del usuario
        let cleaned = query.folding(options: .diacriticInsensitive, locale: .current)
                           .uppercased()
                           .filter { $0.isLetter }
        let normalized = normalize(cleaned)
        let alphagram  = getAnagram(normalized)

        // 2) Búsqueda exacta en el trie
        let exactWords = trieRoot.searchByAlphagram(alphagram)
        results = exactWords.map { denormalize($0) }

        // 3) Búsqueda con una letra extra
        var extendedResults: [ExtraLetterWord] = []
        let letters = "AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ"
        for letter in letters {
            let extended = normalized + String(letter)
            let extAlphagram = getAnagram(extended)
            let matches = trieRoot.searchByAlphagram(extAlphagram)
            for word in matches where !exactWords.contains(word) {
                extendedResults.append(ExtraLetterWord(word: denormalize(word), extraLetter: letter))
            }
        }
        extraLetterResults = extendedResults.sorted { $0.word < $1.word }
    }
}
