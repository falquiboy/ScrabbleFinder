import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AnagramViewModel()

    var body: some View {
        VStack {
            HStack {
                TextField("INGRESA LETRAS O PALABRA", text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0.uppercased() }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)

                Button(action: {
                    if viewModel.query.isEmpty {
                        // No acción necesaria
                    } else {
                        viewModel.query = ""
                        viewModel.results = []
                    }
                }) {
                    Image(systemName: viewModel.query.isEmpty ? "magnifyingglass" : "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()

            Button("Buscar anagramas") {
                viewModel.searchAnagrams()
            }
            .padding()
            .disabled(viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty)

            if viewModel.results.isEmpty {
                Text("No hay resultados")
                    .foregroundColor(.secondary)
                    .padding(.top)
            } else {
                List(viewModel.results, id: \.self) { word in
                    Text(word)
                }
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

