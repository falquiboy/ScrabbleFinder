// TrieNode.swift
import Foundation

public class TrieNode: Codable {
    public var children: [String: TrieNode]
    public var words: [String]?

    public init(children: [String: TrieNode] = [:], words: [String]? = nil) {
        self.children = children
        self.words = words
    }

    /// Busca palabras exactas en el trie que coincidan con un alfagrama
    public func searchByAlphagram(_ alphagram: String) -> [String] {
        var results = [String]()
        search(alphagram, path: "", node: self, results: &results)
        return results
    }

    private func search(_ remaining: String, path: String, node: TrieNode, results: inout [String]) {
        if remaining.isEmpty {
            if let list = node.words {
                results.append(contentsOf: list)
            }
            return
        }

        let nextChar = String(remaining.first!)
        let rest = String(remaining.dropFirst())

        if let child = node.children[nextChar] {
            search(rest, path: path + nextChar, node: child, results: &results)
        }
    }

    /// Genera todas las subsecuencias únicas y no vacías de un alfagrama.
    private func generateSubsequences(for alphagram: String) -> Set<String> {
        var subsequences = Set<String>()
        let sortedAlphagram = Array(alphagram).sorted() // Asegurar orden para consistencia y duplicados

        func findSubsequences(currentIndex: Int, currentSubsequence: String) {
            if currentIndex == sortedAlphagram.count {
                if !currentSubsequence.isEmpty {
                    subsequences.insert(currentSubsequence)
                }
                return
            }

            // Incluir el caracter actual
            findSubsequences(currentIndex: currentIndex + 1, currentSubsequence: currentSubsequence + String(sortedAlphagram[currentIndex]))

            // Excluir el caracter actual
            findSubsequences(currentIndex: currentIndex + 1, currentSubsequence: currentSubsequence)
        }

        findSubsequences(currentIndex: 0, currentSubsequence: "")
        return subsequences
    }

    /// Busca palabras en el trie que coincidan con cualquier sub-alfagrama del alfagrama dado.
    /// Útil para encontrar palabras más cortas que se pueden formar con un subconjunto de las fichas disponibles.
    public func searchBySubAlphagrams(_ alphagram: String) -> [String] {
        let uniqueSubsequences = generateSubsequences(for: alphagram)
        var allWords = Set<String>()

        for sub in uniqueSubsequences {
            let wordsForSubsequence = searchByAlphagram(sub)
            for word in wordsForSubsequence {
                allWords.insert(word)
            }
        }
        return Array(allWords)
    }
}

