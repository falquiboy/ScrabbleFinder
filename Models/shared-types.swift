//
//  SharedTypes.swift
//  ScrabbleFinder
//
// Note: This file should be in the same module as DigraphsUtils.swift
// which defines internalToDigraphs

import SwiftUI
import SafariServices

// MARK: - Safari View Wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Safari Item Model
struct SafariItem: Identifiable {
    let id: String
    let url: URL
    init(_ url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}

// MARK: - Spanish Scrabble Helpers
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

// MARK: - Utility Functions
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
