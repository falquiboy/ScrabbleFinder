import SwiftUI

// MARK: - Word with Hooks Display View
struct WordWithHooksView: View {
    let word: String
    let hooks: WordHooks?
    let showHooks: Bool = true // Could be a toggle later
    
    var body: some View {
        HStack(spacing: 2) {
            if showHooks, let hooks = hooks {
                // Left hooks in lowercase gray
                if !hooks.leftHooks.isEmpty {
                    Text(hooks.leftHooksString.lowercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Main word in bold
                Text(word)
                    .font(.body)
                    .fontWeight(.medium)
                
                // Right hooks in lowercase gray
                if !hooks.rightHooks.isEmpty {
                    Text(hooks.rightHooksString.lowercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Just the word if no hooks or hooks disabled
                Text(word)
                    .font(.body)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Hooks Toggle View (for settings)
struct HooksToggleView: View {
    @Binding var showHooks: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "link")
                .foregroundColor(.secondary)
            Toggle("Mostrar ganchos", isOn: $showHooks)
        }
    }
}

// MARK: - Batch Word with Hooks View (for lists)
struct WordListWithHooksView: View {
    let words: [String]
    let hooksData: [String: WordHooks]
    let showHooks: Bool
    let onWordTap: (String) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(words, id: \.self) { word in
                WordWithHooksView(word: word, hooks: hooksData[word], showHooks: showHooks)
                    .onTapGesture {
                        onWordTap(word)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Sample hooks for preview
        let sampleHooks = WordHooks(
            word: "CASA", 
            leftHooks: ["B", "R"], 
            rightHooks: ["S", "L", "R"]
        )
        
        WordWithHooksView(word: "CASA", hooks: sampleHooks)
        WordWithHooksView(word: "PERRO", hooks: nil)
        
        HooksToggleView(showHooks: .constant(true))
    }
    .padding()
}