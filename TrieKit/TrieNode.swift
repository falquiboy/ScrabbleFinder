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

    /// Returns all words stored in this node and its descendants.
    public func allWords() -> [String] {
        var results: [String] = []
        // Include words at this node
        if let list = self.words {
            results.append(contentsOf: list)
        }
        // Recurse into children
        for child in children.values {
            results.append(contentsOf: child.allWords())
        }
        return results
    }

    /// Search the trie for words matching the given regular expression.
    public func searchByPattern(_ regex: NSRegularExpression) -> [String] {
        // Collect all words and filter by regex
        return allWords().filter { word in
            let range = NSRange(location: 0, length: word.utf16.count)
            return regex.firstMatch(in: word, options: [], range: range) != nil
        }
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
}
