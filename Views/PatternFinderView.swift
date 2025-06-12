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

// MARK: - Pattern Unit para resaltado
private enum PatternUnit {
    case fixed(String)
    case asterisk  // cero o más
    case dot       // exactamente una
}

private func parsePattern(_ pat: String) -> [PatternUnit] {
    var units: [PatternUnit] = []
    let upper = pat.uppercased()
    var i = upper.startIndex
    
    while i < upper.endIndex {
        // Verificar dígrafos primero
        if let next = upper.index(i, offsetBy: 2, limitedBy: upper.endIndex),
           ["CH","LL","RR"].contains(String(upper[i..<next])) {
            units.append(.fixed(String(upper[i..<next])))
            i = next
        } else if upper[i] == "*" {
            units.append(.asterisk)
            i = upper.index(after: i)
        } else if upper[i] == "." || upper[i] == "?" {
            units.append(.dot)
            i = upper.index(after: i)
        } else if upper[i].isLetter {
            units.append(.fixed(String(upper[i])))
            i = upper.index(after: i)
        } else {
            // Ignorar otros caracteres (+, -, :, números)
            i = upper.index(after: i)
        }
    }
    return units
}

// MARK: - Función de resaltado actualizada
private func highlightPatternFilled(_ displayWord: String, _ pattern: String) -> AttributedString {
    // Extraer solo la parte del patrón (antes de la coma si existe)
    let cleanPattern = pattern.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                            .first.map(String.init) ?? pattern
    
    // Quitar operadores +LETRAS, -LETRAS y :n
    var patternOnly = cleanPattern
    patternOnly = patternOnly.replacingOccurrences(of: #"\+[A-ZÑ]+"#, with: "", options: .regularExpression)
    patternOnly = patternOnly.replacingOccurrences(of: #"-[A-ZÑ]+"#, with: "", options: .regularExpression)
    patternOnly = patternOnly.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
    
    let units = parsePattern(patternOnly)
    var attributed = AttributedString(displayWord)
    
    // Dividir la palabra en unidades (considerando dígrafos)
    let wordUnits = splitIntoUnits(displayWord)
    
    var unitIndex = 0
    var charPosition = 0
    
    for unit in units {
        switch unit {
        case .fixed(_):
            // Letra fija - no resaltar
            if unitIndex < wordUnits.count {
                charPosition += wordUnits[unitIndex].count
                unitIndex += 1
            }
            
        case .dot:
            // Exactamente una letra - resaltar en azul
            if unitIndex < wordUnits.count {
                let wildUnit = wordUnits[unitIndex]
                if let startPos = displayWord.index(displayWord.startIndex, offsetBy: charPosition, limitedBy: displayWord.endIndex),
                   let endPos = displayWord.index(startPos, offsetBy: wildUnit.count, limitedBy: displayWord.endIndex),
                   let startIdx = AttributedString.Index(startPos, within: attributed),
                   let endIdx = AttributedString.Index(endPos, within: attributed) {
                    let range = startIdx..<endIdx
                    attributed[range].foregroundColor = Color.blue
                    attributed[range].font = .title3.bold()
                }
                charPosition += wildUnit.count
                unitIndex += 1
            }
            
        case .asterisk:
            // Cero o más letras - resaltar las que quedan en verde
            while unitIndex < wordUnits.count {
                let fillUnit = wordUnits[unitIndex]
                if let startPos = displayWord.index(displayWord.startIndex, offsetBy: charPosition, limitedBy: displayWord.endIndex),
                   let endPos = displayWord.index(startPos, offsetBy: fillUnit.count, limitedBy: displayWord.endIndex),
                   let startIdx = AttributedString.Index(startPos, within: attributed),
                   let endIdx = AttributedString.Index(endPos, within: attributed) {
                    let range = startIdx..<endIdx
                    attributed[range].foregroundColor = Color.green
                    attributed[range].font = .title3.bold()
                }
                charPosition += fillUnit.count
                unitIndex += 1
            }
        }
    }
    return attributed
}

// MARK: - Vista de Ayuda
struct PatternHelpView: View {
    @Binding var isExpanded: Bool
    
    var body: some View {
        DisclosureGroup("Ayuda de Sintaxis", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sintaxis Básica")
                        .font(.footnote.bold())
                    
                    HelpRow(symbol: "*", description: "Cero o más letras", example: "C*A → CASA, CABRA, CA")
                    HelpRow(symbol: ".", description: "Exactamente una letra", example: "C.SA → CASA, COSA")
                    HelpRow(symbol: "Letras", description: "Posición fija", example: "CASA → CASA")
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filtros")
                        .font(.footnote.bold())
                    
                    HelpRow(symbol: "+LETRAS", description: "Debe contener", example: "+AEI → palabras con A, E, I")
                    HelpRow(symbol: "-LETRAS", description: "NO debe contener", example: "-QXZ → sin Q, X, Z")
                    HelpRow(symbol: ":n", description: "Longitud exacta", example: ":5 → 5 letras")
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Atril")
                        .font(.footnote.bold())
                    
                    HelpRow(symbol: ",LETRAS", description: "Usar estas fichas", example: "C.?,AEI → CA?, con A,E,I")
                    HelpRow(symbol: "?", description: "Comodín en atril", example: "CA?,EI → CAE, CAI con comodín")
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ejemplos Combinados")
                        .font(.footnote.bold())
                        .padding(.bottom, 2)
                    
                    ExampleRow(pattern: "C.*A", desc: "Empieza C, termina A")
                    ExampleRow(pattern: "*+CH*", desc: "Contiene dígrafo CH")
                    ExampleRow(pattern: "*.+EI-J:6", desc: "6 letras, con E,I, sin J")
                    ExampleRow(pattern: "*+AEIOU-BCDFG", desc: "Todas las vocales, sin B,C,D,F,G")
                }
            }
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct HelpRow: View {
    let symbol: String
    let description: String
    let example: String?
    
    init(symbol: String, description: String, example: String? = nil) {
        self.symbol = symbol
        self.description = description
        self.example = example
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(symbol)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(width: 60, alignment: .leading)
                Text(description)
                    .font(.caption)
                Spacer()
            }
            if let example = example {
                Text(example)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 68)
            }
        }
    }
}

struct ExampleRow: View {
    let pattern: String
    let desc: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
            Text("→")
                .foregroundColor(.gray)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Vista Principal
struct PatternFinderView: View {
    @EnvironmentObject var patternVM: PatternViewModel
    @State private var pattern = ""
    @FocusState private var isPatternFocused: Bool
    @State private var selectedItem: SafariItem?
    @State private var expandedLengths: Set<Int> = []
    @State private var showHelp = false
    @State private var hasSearched = false

    private func copyAllWords() {
        let all = patternVM.resultsByLength.values
            .flatMap { $0.map { patternVM.denormalize($0.word) } }
        #if canImport(UIKit)
        UIPasteboard.general.string = all.joined(separator: "\n")
        #endif
    }
    
    private var totalResults: Int {
        patternVM.resultsByLength.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("BUSCADOR POR PATRÓN")
                .font(.title).bold()

            // Search bar
            HStack {
                TextField("INGRESA PATRÓN",
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
                    searchPattern()
                }
                .overlay(
                    HStack {
                        Spacer()
                        if !pattern.isEmpty {
                            Button {
                                pattern = ""
                                patternVM.resultsByLength.removeAll()
                                hasSearched = false
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
                    hasSearched = false
                }

                Button {
                    searchPattern()
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
                
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
            }
            .padding(.horizontal)

            // Help section
            PatternHelpView(isExpanded: $showHelp)
                .padding(.horizontal)

            // Toggle for > 8 letters
            HStack {
                Toggle("Mostrar > 8 letras", isOn: $patternVM.showLongWords)
                Spacer()
                if hasSearched {
                    Text("\(totalResults) palabras")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if hasSearched && patternVM.resultsByLength.isEmpty {
                        Text("No se encontraron palabras con este patrón")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    
                    ForEach(patternVM.resultsByLength.keys.sorted(by: >), id: \.self) { len in
                        if len <= 8 || patternVM.showLongWords {
                            // Break down complex expression
                            let results = patternVM.resultsByLength[len] ?? []
                            let isExpanded = expandedLengths.contains(len)
                            
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { isExpanded },
                                    set: { newVal in
                                        if newVal {
                                            expandedLengths.insert(len)
                                        } else {
                                            expandedLengths.remove(len)
                                        }
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
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    Text("\(len) letras")
                                        .font(.title3)
                                        .bold()
                                    Text("(\(results.count))")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
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
        .padding(.vertical)
        .onAppear {
            // No expandir automáticamente al inicio
            expandedLengths.removeAll()
        }
        .onChange(of: Array(patternVM.resultsByLength.keys.sorted())) { _, newKeys in
            // Expandir solo las primeras 3 longitudes si hay resultados
            if !newKeys.isEmpty && hasSearched {
                expandedLengths = Set(newKeys.prefix(3))
            }
        }
    }
    
    private func searchPattern() {
        patternVM.query = pattern
        patternVM.search()
        hasSearched = true
        isPatternFocused = false
        #if canImport(UIKit)
        UIApplication.shared.dismissKeyboard()
        #endif
    }
}
