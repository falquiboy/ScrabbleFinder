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

// MARK: – ViewModel ----------------------------------------------------------

final class AnagramViewModel: ObservableObject {

    // Publicado a la vista
    @Published var query: String = ""
    @Published var results: [String] = []                    // palabras exactas
    @Published var extraLetterResults: [ExtraLetterWord] = []// +1 ficha
    @Published var wildcardResults: [WildcardWord] = []      // con “?”

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

            // 2-a  exactas
            let alpha      = alphagram(of: normalized)
            let exactRaw   = trieRoot.searchByAlphagram(alpha)
            results        = exactRaw.map { denormalize($0) }

            // 2-b  +1 ficha
            var extras: [ExtraLetterWord] = []
            let letters = "AÇBCDEFGHIJKLMNOPQRSTUVWXYZÑ"
            for letter in letters {
                let extAlpha = alphagram(of: normalized + String(letter))
                let matches  = trieRoot.searchByAlphagram(extAlpha)
                for w in matches where !exactRaw.contains(w) {
                    extras.append(ExtraLetterWord(word: denormalize(w),
                                                 extraLetter: letter))
                }
            }
            extraLetterResults = extras.sorted { $0.word < $1.word }
            return
        }

        // --------------------------------------------------------------------
        // 3) Con comodines (hasta 2 “?”)
        // --------------------------------------------------------------------
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
