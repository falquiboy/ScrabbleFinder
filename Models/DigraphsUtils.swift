// DigraphUtils.swift
// Backend logic for internal digraph handling

import Foundation

// MARK: – Mappings
let digraphsToInternal: [String: Character] = [
    "CH": "Ç",
    "LL": "K",
    "RR": "W"
]

let internalToDigraphs: [Character: String] = [
    "Ç": "CH",
    "K": "LL",
    "W": "RR"
]

// MARK: – Alphabet order for anagram generation
private let alphabetOrder: [Character] = Array("AEIOUBCÇDFGHJLKMNÑPQRWSTVXYZ")
private let orderMap: [Character: Int] = {
    var m = [Character: Int]()
    for (i, c) in alphabetOrder.enumerated() {
        m[c] = i
    }
    return m
}()

// MARK: – Normalization (user input → internal)
func normalize(_ input: String) -> String {
    var output = input.uppercased()
    for (digraph, replacement) in digraphsToInternal {
        output = output.replacingOccurrences(of: digraph, with: String(replacement))
    }
    return output
}

// MARK: – Anagram generation using custom order
func getAnagram(_ input: String) -> String {
    let chars = input.map { $0 }
    let sorted = chars.sorted { a, b in
        let ia = orderMap[a] ?? Int.max
        let ib = orderMap[b] ?? Int.max
        return ia < ib
    }
    return String(sorted)
}

// MARK: – Denormalization (internal → display)
func denormalize(_ input: String) -> String {
    var output = input
    for (internalChar, digraph) in internalToDigraphs {
        output = output.replacingOccurrences(of: String(internalChar), with: digraph)
    }
    return output
}

