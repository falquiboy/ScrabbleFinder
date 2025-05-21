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
}

