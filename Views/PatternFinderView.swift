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
  // Strip off any rack letters after comma so we only parse the pattern itself
  let rawPattern = pattern.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                       .first.map(String.init) ?? pattern
  let units = parsePattern(rawPattern)
  var attributed = AttributedString(displayWord)
  let displayCount = attributed.characters.count
  let fixedAndWildcardCount = units.reduce(0) { total, unit in
    switch unit {
    case .fixed(let txt):
      return total + txt.count
    case .wildcard:
      return total + 1
    case .hyphen:
      return total
    }
  }
  let fillLength = max(0, displayCount - fixedAndWildcardCount)
  var cursor = 0
  for unit in units {
    switch unit {
    case .fixed(let txt):
      cursor += txt.count

    case .wildcard:
      guard cursor < attributed.characters.count else { continue }
      let start = attributed.characters.index(attributed.startIndex, offsetBy: cursor)
      let end = attributed.characters.index(start, offsetBy: 1)
      let range = start..<end
      attributed[range].foregroundColor = Color.red
      attributed[range].font = .title3.bold()
      cursor += 1

    case .hyphen:
      guard fillLength > 0 else { continue }
      let start = attributed.characters.index(attributed.startIndex, offsetBy: cursor)
      let end = attributed.characters.index(start, offsetBy: fillLength)
      let range = start..<end
      attributed[range].foregroundColor = Color.blue
      attributed[range].font = .title3.bold()
      cursor += fillLength
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
                    UIApplication.shared.dismissKeyboard()
                    isPatternFocused = false
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
        .onAppear { isPatternFocused = true }
        .padding()
        .onAppear {
            expandedLengths = Set(patternVM.resultsByLength.keys)
        }
        .onChange(of: Array(patternVM.resultsByLength.keys.sorted())) { _, newKeys in
            expandedLengths = Set(newKeys)
        }
    }
}
