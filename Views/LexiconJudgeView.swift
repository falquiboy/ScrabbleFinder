//
//  LexiconJudgeView.swift
//  ScrabbleFinder
//
//  Created by Isaac Falconer on 2025.05.24.
//

import SwiftUI

struct LexiconJudgeView: View {
    @EnvironmentObject var anagramVM: AnagramViewModel   // lo inyectaremos luego
    @State private var inputText = ""
    @State private var results: [(word: String, valid: Bool)] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                Text("JUEZ DE LÉXICO")
                    .font(.title).bold()
                    .multilineTextAlignment(.center)

                // Campo para escribir una o más palabras
                TextField("Escribe palabras separadas por espacio",
                          text: Binding(
                              get: { inputText },
                              set: { inputText = $0.uppercased() }
                          ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .focused($isInputFocused)
                .submitLabel(.go)
                .onSubmit(validate)
                .overlay(
                    HStack {
                        Spacer()
                        if !inputText.isEmpty {
                            Button {
                                inputText = ""
                                results.removeAll()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                )

                Button("Validar", action: validate)
                    .buttonStyle(.borderedProminent)

                if !results.isEmpty {
                    let allValid = results.allSatisfy { $0.valid }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results, id: \.word) { res in
                            Text(res.word)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(allValid ? Color.green : Color.red)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Acción principal
    private func validate() {
        let words = inputText
            .uppercased()
            .split{ !$0.isLetter }  // separa por no-letras
            .map(String.init)

        results = words.map { word in
            (word, anagramVM.isValid(word))   // <-- aún por crear
        }
    }
}

struct LexiconJudgeView_Previews: PreviewProvider {
    static var previews: some View {
        LexiconJudgeView()
            .environmentObject(AnagramViewModel())
    }
}
