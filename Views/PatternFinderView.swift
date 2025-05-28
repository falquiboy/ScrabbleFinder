//
//  PatternFinderView.swift
//  ScrabbleFinder
//
//  Created by Isaac Falconer on 2025.05.25.
//


import SwiftUI
import SafariServices
#if canImport(UIKit)
import UIKit

// MARK: - Keyboard Dismiss Extension
extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

private enum PatternUnit {
  case fixed(String)
  case hyphen
  case wildcard
}

private func parsePattern(_ pat: String) -> [PatternUnit] {
  var units: [PatternUnit] = []
  let upper = pat.uppercased()
  var i = upper.startIndex
  while i < upper.endIndex {
    // Two‐letter digraph?
    if let next = upper.index(i, offsetBy: 2, limitedBy: upper.endIndex),
       ["CH","LL","RR"].contains(String(upper[i..<next])) {
      units.append(.fixed(String(upper[i..<next])))
      i = next

    // Wildcard "*"
    } else if upper[i] == "*" {
      units.append(.wildcard)
      i = upper.index(after: i)

    // Hyphen "-"
    } else if upper[i] == "-" {
      units.append(.hyphen)
      i = upper.index(after: i)

    // Single fixed letter
    } else {
      units.append(.fixed(String(upper[i])))
      i = upper.index(after: i)
    }
  }
  return units
}

private func highlightPatternFilled(_ displayWord: String, _ pattern: String) -> AttributedString {
    let rawPattern = pattern.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                         .first.map(String.init) ?? pattern
    let units = parsePattern(rawPattern)
    var attributed = AttributedString(displayWord)
    
    // Usar splitIntoUnits para manejar dígrafos correctamente
    let wordUnits = splitIntoUnits(displayWord)
    let fixedAndWildcardCount = units.reduce(0) { total, unit in
        switch unit {
        case .fixed(let txt): return total + splitIntoUnits(txt).count
        case .wildcard: return total + 1
        case .hyphen: return total
        }
    }
    let fillLength = max(0, wordUnits.count - fixedAndWildcardCount)
    
    var unitIndex = 0
    var charPosition = 0
    
    for unit in units {
        switch unit {
        case .fixed(let txt):
            let fixedUnits = splitIntoUnits(txt)
            for _ in fixedUnits {
                if unitIndex < wordUnits.count {
                    charPosition += wordUnits[unitIndex].count
                    unitIndex += 1
                }
            }
            
        case .wildcard:
            if unitIndex < wordUnits.count {
                let wildUnit = wordUnits[unitIndex]
                let startPos = displayWord.index(displayWord.startIndex, offsetBy: charPosition)
                let endPos = displayWord.index(startPos, offsetBy: wildUnit.count)
                let range = AttributedString.Index(startPos, within: attributed)!..<AttributedString.Index(endPos, within: attributed)!
                attributed[range].foregroundColor = Color.red
                attributed[range].font = .title3.bold()
                charPosition += wildUnit.count
                unitIndex += 1
            }
            
        case .hyphen:
            for _ in 0..<fillLength {
                if unitIndex < wordUnits.count {
                    let fillUnit = wordUnits[unitIndex]
                    let startPos = displayWord.index(displayWord.startIndex, offsetBy: charPosition)
                    let endPos = displayWord.index(startPos, offsetBy: fillUnit.count)
                    let range = AttributedString.Index(startPos, within: attributed)!..<AttributedString.Index(endPos, within: attributed)!
                    attributed[range].foregroundColor = Color.blue
                    attributed[range].font = .title3.bold()
                    charPosition += fillUnit.count
                    unitIndex += 1
                }
            }
        }
    }
    return attributed
}

struct PatternFinderView: View {
    @EnvironmentObject var patternVM: PatternViewModel
    @State private var pattern = ""
    @FocusState private var isPatternFocused: Bool
    @State private var selectedItem: SafariItem?
    @State private var expandedLengths: Set<Int> = []

    private func copyAllWords() {
        let all = patternVM.resultsByLength.values
            .flatMap { $0.map { patternVM.denormalize($0.word) } }
        #if canImport(UIKit)
        UIPasteboard.general.string = all.joined(separator: "\n")
        #endif
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("BUSCADOR POR PATRÓN")
                .font(.title).bold()

            // Search bar -------------------------------------------------
            HStack {
                TextField("INGRESA PATRÓN (- y *)",
                          text: Binding(
                              get: { pattern },
                              set: { pattern = $0.uppercased() }
                          ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .focused($isPatternFocused)
                .submitLabel(.search)
                .onSubmit {
                    patternVM.query = pattern
                    patternVM.search()
                    isPatternFocused = false
                    #if canImport(UIKit)
                    UIApplication.shared.dismissKeyboard()
                    #endif
                }
                .overlay(
                    HStack {
                        Spacer()
                        if !pattern.isEmpty {
                            Button {
                                pattern = ""
                                patternVM.resultsByLength.removeAll()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                )
                .onChange(of: pattern) {
                    patternVM.resultsByLength.removeAll()
                }

                Button {
                    patternVM.query = pattern
                    patternVM.search()
                    isPatternFocused = false
                    #if canImport(UIKit)
                    UIApplication.shared.dismissKeyboard()
                    #endif
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                }

                Button {
                    copyAllWords()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                }
                .disabled(patternVM.resultsByLength.isEmpty)
            }
            .padding()

            // Toggle for > 8 letters ------------------------------------
            HStack {
                Toggle("Mostrar > 8 letras", isOn: $patternVM.showLongWords)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(patternVM.resultsByLength.keys.sorted(by: >), id: \.self) { len in
                        if len <= 8 || patternVM.showLongWords {
                            let results = patternVM.resultsByLength[len] ?? []
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedLengths.contains(len) },
                                    set: { newVal in
                                        if newVal { expandedLengths.insert(len) }
                                        else { expandedLengths.remove(len) }
                                    }
                                )
                            ) {
                                let columns = len > 8
                                    ? [GridItem(.flexible())]
                                    : [GridItem(.flexible()), GridItem(.flexible())]
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(results, id: \.word) { result in
                                        let display = patternVM.denormalize(result.word)
                                        let highlighted = highlightPatternFilled(display, pattern)
                                        Text(highlighted)
                                            .font(.title3)
                                            .onTapGesture {
                                                if let url = URL(string: "https://dle.rae.es/\(display)") {
                                                    selectedItem = SafariItem(url)
                                                }
                                            }
                                            .padding(4)
                                            .frame(maxWidth: .infinity)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(6)
                                    }
                                }
                            } label: {
                                Text("\(len) letras (\(results.count))")
                                    .font(.title3)
                                    .bold()
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .sheet(item: $selectedItem) { item in
                SafariView(url: item.url)
                    .presentationDetents([.medium, .large])
            }
        }
        .onTapGesture {
            #if canImport(UIKit)
            UIApplication.shared.dismissKeyboard()
            #endif
        }
        .padding()
        .onAppear {
            expandedLengths = Set(patternVM.resultsByLength.keys)
        }
        .onChange(of: Array(patternVM.resultsByLength.keys.sorted())) { _, newKeys in
            expandedLengths = Set(newKeys)
        }
    }
}
