import SwiftUI
import TrieKit

struct RootView: View {
    // 1️⃣ ViewModel compartido para todas las pantallas
    @StateObject private var anagramVM: AnagramViewModel
    @StateObject private var patternVM: PatternViewModel

    init() {
        let anagram = AnagramViewModel()
        _anagramVM = StateObject(wrappedValue: anagram)
        _patternVM = StateObject(
            wrappedValue: PatternViewModel(
                anagramModel: anagram
            )
        )
    }

    var body: some View {
        TabView {
            // Pestaña 1: Anagramas
            ContentView()
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Anagramas", systemImage: "text.magnifyingglass")
                }

            // Pestaña 2: Validador de léxico
            LexiconJudgeView()
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Validador", systemImage: "checkmark.shield")
                }
            PatternFinderView()
                .environmentObject(patternVM)
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Patrones", systemImage: "text.redaction")
                }

            // (Opcional) Pestaña 3: Listas, etc.
        }
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
