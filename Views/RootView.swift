import SwiftUI
import TrieKit

struct RootView: View {
    // 1️⃣ ViewModel compartido para todas las pantallas
    @StateObject private var anagramVM: AnagramViewModel
    @StateObject private var patternVM: PatternViewModel
    @State private var selectedTab = 0

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
        TabView(selection: $selectedTab) {
            // Pestaña 1: Anagramas
            ContentView()
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Anagramas", systemImage: "text.magnifyingglass")
                }
                .tag(0)

            // Pestaña 2: Validador de léxico
            LexiconJudgeView()
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Validador", systemImage: "checkmark.shield")
                }
                .tag(1)
            
            PatternFinderView()
                .environmentObject(patternVM)
                .environmentObject(anagramVM)
                .tabItem {
                    Label("Patrones", systemImage: "text.redaction")
                }
                .tag(2)
            
            // Nueva interfaz unificada (sin dependencias)
            UnifiedSearchView()
                .tabItem {
                    Label("Unificada", systemImage: "sparkles")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) {
            hideKeyboard()
        }
    }
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
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
