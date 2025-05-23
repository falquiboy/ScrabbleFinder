import Foundation
import TrieKit

// MARK: – Model helpers ------------------------------------------------------

struct ExtraLetterWord: Identifiable {
    let id = UUID()
    let word: String
    let extraLetter: Character
}

/// Resultado con comodines “?”; guarda las letras que sustituyeron cada “?”
struct WildcardWord: Identifiable {
    let id = UUID()
    let word: String
    let wildcardLetters: [Character]   // mismo orden que los “?” del query
}

struct ShorterWordGroup: Identifiable {
    let id: Int // Using length as ID, assuming length is unique for groups
    let length: Int
    var words: [String] // Already sorted alphabetically
}

// MARK: – ViewModel ----------------------------------------------------------

final class AnagramViewModel: ObservableObject {

    // Publicado a la vista
    @Published var query: String = ""
    @Published var results: [String] = []
    @Published var extraLetterResults: [ExtraLetterWord] = []
    @Published var wildcardResults: [WildcardWord] = []
    @Published var shorterWordsResults: [String] = [] // Retained for total count and copyAllWords
    @Published var groupedShorterWords: [ShorterWordGroup] = [] // For grouped display
    @Published var enableShorterWords: Bool = false

    // Trie raíz
    private let trieRoot: TrieNode

    // Conversión de dígrafos ⇆ forma interna
    private let digraphsToInternal: [String: Character] = ["CH":"Ç", "LL":"K", "RR":"W"]
    private let internalToDigraphs: [Character: String] = ["Ç":"CH", "K":"LL", "W":"RR"]

    // Orden especial para los alfagramas
    private let alphaOrder = "AEIOUBCÇDFGHJLKMNÑPQRWSTVXYZ"
    private lazy var orderPos: [Character: Int] =
        Dictionary(uniqueKeysWithValues: alphaOrder.enumerated()
                                                .map { ($0.element, $0.offset) })

    // ------------------------------------------------------------------------
    // Init – carga trie.bin
    // ------------------------------------------------------------------------
    init() {
        guard let url  = Bundle.main.url(forResource: "trie", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            fatalError("❌ No se encontró trie.bin en el bundle")
        }
        do {
            trieRoot = try PropertyListDecoder().decode(TrieNode.self, from: data)
        } catch {
            fatalError("❌ Error decodificando trie.bin: \(error)")
        }
    }

    // ------------------------------------------------------------------------
    // Búsqueda principal
    // ------------------------------------------------------------------------
    func searchAnagrams() {

        // Limpia salidas previas
        results.removeAll()
        extraLetterResults.removeAll()
        wildcardResults.removeAll()
        shorterWordsResults.removeAll()
        groupedShorterWords.removeAll() // Clear new grouped results

        // --------------------------------------------------------------------
        // 1) Procesa texto del usuario → internalBuffer + wildcardCount
        // --------------------------------------------------------------------
        var wildcardCount = 0
        var internalBuffer: [Character] = []

        let upper = Array(query.uppercased())
        var i = 0
        while i < upper.count {
            let ch = upper[i]

            if ch == "?" {                       // comodín
                wildcardCount += 1
                i += 1
                continue
            }

            // Dígrafos CH/LL/RR
            if i + 1 < upper.count {
                let next = upper[i + 1]
                if ch == "C", next == "H" {
                    internalBuffer.append("Ç"); i += 2; continue
                }
                if ch == "L", next == "L" {
                    internalBuffer.append("K"); i += 2; continue
                }
                if ch == "R", next == "R" {
                    internalBuffer.append("W"); i += 2; continue
                }
            }

            if ch.isLetter {                     // Incluye Ñ
                internalBuffer.append(ch)
            }
            i += 1
        }

        let normalized = String(internalBuffer)

        // --------------------------------------------------------------------
        // 2) Sin comodines
        // --------------------------------------------------------------------
        if wildcardCount == 0 {
            if enableShorterWords {
                // --- Calculate and populate shorterWordsResults ---
                // Ensure results and extraLetterResults are empty
                results.removeAll()
                extraLetterResults.removeAll()

                // Assuming trieRoot.searchBySubAlphagrams takes the non-alphagrammed 'normalized' string
                // and handles alphagramming internally if needed for its logic.
                let foundShorterInternal = trieRoot.searchBySubAlphagrams(normalized)
                
                // Filter for words strictly shorter than the query and ensure uniqueness.
                // The check against `results` is no longer needed as `results` will be empty here.
                let shorterAndUnique = Set(foundShorterInternal
                    .map { denormalize($0) }
                    .filter { $0.count < query.count }) // query.count is the original user input length
                
                shorterWordsResults = Array(shorterAndUnique).sorted {
                    if $0.count != $1.count {
                        return $0.count > $1.count // Descendente por longitud
                    }
                    // Using basic alphabetical sort as spanishScrabbleOrder is not in this file.
                    // This can be refined if sorting helpers are moved/made accessible.
                    return $0 < $1 // Alfabéticamente para misma longitud
                }
                
                // Transform flat shorterWordsResults to groupedShorterWords
                let groups = Dictionary(grouping: shorterWordsResults, by: { $0.count })
                groupedShorterWords = groups.map { ShorterWordGroup(id: $0.key, length: $0.key, words: $0.value) }
                                            .sorted { $0.length > $1.length } // Sort groups by length descending

            } else {
                // --- Calculate and populate results (exact) and extraLetterResults ---
                // Ensure shorterWordsResults and groupedShorterWords are empty
                shorterWordsResults.removeAll()
                groupedShorterWords.removeAll()

                let alpha = alphagram(of: normalized)
                let exactRaw = trieRoot.searchByAlphagram(alpha)
                // Using basic alphabetical sort for results
                results = exactRaw.map { denormalize($0) }.sorted()

                var extras: [ExtraLetterWord] = []
                let letters = "AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ" // Consider moving this to a constant
                for letter in letters {
                    let extAlpha = alphagram(of: normalized + String(letter))
                    let matches = trieRoot.searchByAlphagram(extAlpha)
                    for w in matches where !exactRaw.contains(w) { // Avoid duplicates from exactRaw
                        extras.append(ExtraLetterWord(word: denormalize(w),
                                                     extraLetter: letter))
                    }
                }
                // Using basic alphabetical sort for extraLetterResults word
                extraLetterResults = extras.sorted { $0.word < $1.word }
            }
        } else {
            // --- Wildcard logic ---
            // Ensure other result arrays are clear
            results.removeAll()
            extraLetterResults.removeAll()
            shorterWordsResults.removeAll()

            // (Original wildcard logic remains here)
        let letters = Array("AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ")
        var seen   = Set<String>()
        var found: [WildcardWord] = []

        func process(_ candidate: String, _ subs: [Character]) {
            let alpha   = alphagram(of: candidate)
            let matches = trieRoot.searchByAlphagram(alpha)
            for w in matches where !seen.contains(w) {
                seen.insert(w)
                found.append(WildcardWord(word: denormalize(w),
                                          wildcardLetters: subs))
            }
        }

        switch wildcardCount {
        case 1:
            for l in letters { process(normalized + String(l), [l]) }
        case 2:
            for l1 in letters {
                for l2 in letters {
                    process(normalized + String(l1) + String(l2), [l1, l2])
                }
            }
        default: break
        }

        // Using basic alphabetical sort for wildcardResults word
        wildcardResults = found.sorted { $0.word < $1.word }
    }

    // ------------------------------------------------------------------------
    // MARK: – Helpers
    // ------------------------------------------------------------------------

    /// Alfagrama con el orden especial
    private func alphagram(of word: String) -> String {
        String(word.sorted { orderPos[$0, default: 999] < orderPos[$1, default: 999] })
    }

    /// Convierte forma interna (Ç/K/W) a dígrafos “bonitos” para la UI.
    private func denormalize(_ word: String) -> String {
        var out = ""
        for ch in word {
            if let digraph = internalToDigraphs[ch] {
                out += digraph
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
