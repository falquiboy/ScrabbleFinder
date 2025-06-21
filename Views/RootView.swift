import SwiftUI
import TrieKit

struct RootView: View {
    var body: some View {
        UnifiedSearchView()
            .onAppear {
                // Inicializar carga del trie inmediatamente al arrancar la app
                preloadTrie()
            }
    }
    
    private func preloadTrie() {
        // Crear un AnagramViewModel temporal para inicializar el trie
        let _ = AnagramViewModel()
        print("🚀 Iniciando carga del trie al arrancar la app")
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        let anagram = AnagramViewModel()
        let pattern = PatternViewModel(anagramModel: anagram)
        return RootView()
            .environmentObject(anagram)
            .environmentObject(pattern)
    }
}
