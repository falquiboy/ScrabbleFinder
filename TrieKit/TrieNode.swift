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

    /// Searches the trie for words matching a pattern with wildcards and rack constraints.
    /// - Parameters:
    ///   - pattern: The normalized pattern string (using internal characters like Ç, K, W).
    ///   - patternIndex: The current index in the pattern string.
    ///   - rack: A mutable array of remaining rack characters (in internal character format).
    ///   - node: The current trie node.
    ///   - wildcardsUsed: The number of wildcards ('?') used so far.
    /// - Returns: An array of matching words (in internal character format).
    public func searchWithWildcards(pattern: String, patternIndex: Int, rack: inout [Character], node: TrieNode, wildcardsUsed: Int) -> [String] {
        // Base case: If we've reached the end of the pattern
        if patternIndex == pattern.count {
            return node.words ?? [] // Return words at this node if any
        }

        var results: [String] = []
        let patternChar = pattern[pattern.index(pattern.startIndex, offsetBy: patternIndex)]

        // Handle wildcard '?'
        if patternChar == "?" {
            // Iterate through all possible internal characters (a-z, Ç, K, W)
            let possibleChars = "ABCÇDEFGHIJKLMNOPQRSTUVWXYZÑKW" // Include your custom digraph chars
            for char in possibleChars {
                // Check if the character is in the remaining rack
                if let rackIndex = rack.firstIndex(of: char) {
                    // Use character from rack
                    var newRack = rack
                    newRack.remove(at: rackIndex)
                    if let childNode = node.children[String(char)] {
                        results.append(contentsOf: searchWithWildcards(pattern: pattern, patternIndex: patternIndex + 1, rack: &newRack, node: childNode, wildcardsUsed: wildcardsUsed))
                    }
                } else if wildcardsUsed < 2 {
                    // Use a blank tile for the wildcard
                    if let childNode = node.children[String(char)] {
                        results.append(contentsOf: searchWithWildcards(pattern: pattern, patternIndex: patternIndex + 1, rack: &rack, node: childNode, wildcardsUsed: wildcardsUsed + 1))
                    }
                }
            }
        } else {
            // Handle regular character
            if let childNode = node.children[String(patternChar)] {
                results.append(contentsOf: searchWithWildcards(pattern: pattern, patternIndex: patternIndex + 1, rack: &rack, node: childNode, wildcardsUsed: wildcardsUsed))
            }
        }

        return results
    }
}
