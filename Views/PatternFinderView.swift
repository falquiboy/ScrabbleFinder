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
#endif

struct PatternFinderView: View {
    @EnvironmentObject var patternVM: PatternViewModel
    @State private var pattern = ""
    @FocusState private var isPatternFocused: Bool
    @State private var selectedItem: SafariItem?
    @State private var expandedLengths: Set<Int> = []

    private func copyAllWords() {
        let all = patternVM.resultsByLength.values
            .flatMap { $0.map { patternVM.denormalize($0) } }
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
                            let internalWords = patternVM.resultsByLength[len]!
                            let denormedWords = internalWords.map { patternVM.denormalize($0) }
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
                                    ForEach(denormedWords, id: \.self) { displayWord in
                                        Text(displayWord)
                                            .font(.title3)
                                            .onTapGesture {
                                                if let url = URL(string: "https://dle.rae.es/\(displayWord)") {
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
                                Text("\(len) letras (\(denormedWords.count))")
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
        .onChange(of: patternVM.resultsByLength) { new in
            expandedLengths = Set(new.keys)
        }
    }
}
