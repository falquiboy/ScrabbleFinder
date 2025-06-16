# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- **Build the project**: Open in Xcode and use Cmd+B or Product → Build
- **Run the app**: Use Cmd+R in Xcode or Product → Run
- **Clean build**: Cmd+Shift+K or Product → Clean Build Folder

This is a standard iOS project with no special build scripts or external dependencies.

## Architecture Overview

ScrabbleFinder is a Spanish Scrabble word finder iOS app built with SwiftUI. The app has four main features accessed through a TabView, with the newest "Unificada" tab providing an optimized unified search experience:

### Core Components

1. **TrieKit Framework**: Custom framework containing trie data structures for efficient word searches
   - `TrieNode.swift`: Core trie implementation with alphagram search, pattern matching, and wildcard support
   - `TrieKit.swift`: Framework entry point (currently minimal)

2. **Data Sources**: 
   - `trie.bin`: Serialized trie data structure for fast in-memory searches
   - `scrabble_words.sqlite`: SQLite database as fallback when trie isn't loaded yet
   - `scrabble_hooks.sqlite`: Separate SQLite database containing word hooks (extensions and reductions)

3. **View Models**:
   - `AnagramViewModel`: Handles anagram searches, validation, and shorter word generation
   - `PatternViewModel`: Manages pattern-based word searches with rack constraints and include/exclude letter filtering
   - `UnifiedSearchModel`: Next-generation unified search model with automatic mode detection and hooks integration
   - `DataManager`: Centralized data access layer managing trie, words database, and hooks database

4. **Views**:
   - `RootView`: Main TabView container with shared view models
   - `ContentView`: Anagram search interface
   - `LexiconJudgeView`: Word validation interface  
   - `PatternFinderView`: Pattern search with rack constraints and advanced filtering
   - `UnifiedSearchView`: Next-generation unified interface with optimized layout and hooks visualization

### Key Architecture Patterns

- **Spanish Digraphs**: Special handling for CH, LL, RR converted to internal representations (Ç, K, W)
- **Alphagram Search**: Words indexed by sorted character signatures for anagram matching
- **Dual Data Sources**: Trie for performance, SQLite for reliability during trie loading
- **Shared State**: View models passed between tabs via `@EnvironmentObject`
- **Automatic Mode Detection**: OmniSearch automatically detects search intent based on input patterns (spaces for judge mode, dots for pattern mode, default to anagram mode)

### Internal Character Mapping

The app normalizes Spanish digraphs for internal processing:
- CH → Ç
- LL → K  
- RR → W

This mapping is handled in `AnagramViewModel` and `DigraphsUtils.swift`.

### Search Features

- **Exact anagrams**: Find words using exactly the input letters
- **Extra letter search**: Find words using input letters + one additional letter
- **Wildcard search**: Support for "?" wildcards (up to 2)
- **Pattern search**: Match patterns with rack letter constraints
- **Include/Exclude letters**: Advanced filtering with `+LETTERS` (must contain) and `-LETTERS` (must not contain)
- **Shorter words**: Generate sub-anagrams of different lengths

### Include/Exclude Letter System

The pattern search supports sophisticated letter filtering implemented in `PatternViewModel.swift`:

- **Include syntax**: `+LETTERS` requires specific letters (e.g., `+AEI` needs A, E, and I)
- **Exclude syntax**: `-LETTERS` forbids specific letters (e.g., `-QXZ` excludes Q, X, Z)  
- **Multiplicity support**: `+UU` requires at least two U's
- **Digraph support**: `+(CH)` requires CH digraph, `-(RR)` excludes RR digraph
- **Combined filtering**: `*+AEIOU-BCDFG:6` finds 6-letter words with all vowels but no B/C/D/F/G

The filtering logic uses regex lookaheads for efficient constraint checking and supports the internal character mapping for Spanish digraphs.

### OmniSearch Feature

The OmniSearch feature, introduced in the latest update, provides a unified search interface that automatically detects the user's search intent:

- **Automatic Mode Detection**:
  - Input with spaces → Judge mode (word validation)
  - Input with dots (.) → Pattern search mode  
  - Input with wildcards (?) → Anagram mode with wildcard support
  - Default fallback → Anagram mode

- **Unified Results**: Single interface that adapts to show:
  - Anagram results as simple word lists or grouped by length
  - Pattern results grouped by word length with highlighting
  - Context-sensitive help based on detected mode

- **Smart UI Adaptation**: 
  - Shows relevant toggles based on mode (e.g., "Show > 8 letters" for patterns, "Show shorter words" for anagrams)
  - Dynamic help text that changes based on detected search mode
  - Unified result counter across all modes

The OmniSearch implementation uses `OmniSearchResult` enum to handle different result types and `OmniSearchMode` enum for mode detection, providing a clean separation between search logic and UI presentation.

### Wildcard Support in OmniSearch

The OmniSearch model includes enhanced wildcard support for pattern search mode:

- **Rack Wildcards**: Pattern search mode supports up to 2 wildcards (`?`) in the rack portion
- **Smart Wildcard Usage**: Wildcards are only consumed when specific rack letters cannot satisfy word requirements
- **Seamless Integration**: Works with all existing pattern features (include/exclude letters, fixed lengths, etc.)
- **Mode Detection**: Input like `P.S.,AER?` automatically triggers pattern mode and enables wildcard rack processing

Example usage: `*,AEIO??` finds words using letters A,E,I,O plus up to 2 wildcards for any pattern.

**Important Character Distinction:**
- **Dots (`.`)**: Used in pattern portion for fixed wildcard positions (e.g., `M...N` matches 5-letter words starting with M, ending with N)
- **Question marks (`?`)**: Used ONLY in rack portion for rack wildcards (e.g., `M...N,AEIO?` uses rack A,E,I,O plus one wildcard)

This distinction ensures clear separation between pattern structure (fixed positions) and rack flexibility (any letter substitution).

## Unified Search Interface ("+Léxico" Tab)

The newest and most advanced interface, designed for maximum efficiency and visual appeal.

### Design Philosophy
- **Space Optimization**: Minimal UI elements to maximize result display area
- **Visual Consistency**: Perfect square hooks in organized grids
- **Smart Adaptation**: Dynamic sizing based on word length and hook count
- **Clean Architecture**: No dependencies on legacy components

### Key Features

#### Compact Interface
- **Title**: Fixed "+Léxico" (no dynamic titles)
- **Search Input**: Integrated with external magnifying glass button
- **Clear Button**: 32×32px touch area with larger icon
- **Minimal Spacing**: Optimized vertical spacing for more results

#### Hooks Visualization System
- **Hook Enclosures**: Perfect 26×26px squares designed to fit "CH" digraph
- **Grid Layout**: Exactly 4 hooks per row (except 1-2 hooks)
- **Color Scheme**: Dark background (80% opacity) with bold white text
- **Dynamic Height**: Calculated per result based on hook count

#### Intelligent Sizing
- **Proportional Allocation**: Short words get more hook space, long words get more word space
- **Word Sizing Ratios**:
  - Short words (≤3 letters): 30% of available space
  - Medium words (4-6 letters): 50% of available space  
  - Long words (7+ letters): 70% of available space
- **Hook Columns**: Dynamically sized based on actual hook count

#### Layout Formula
```
Height = max(36px, rows × 26px + 10px)
Hook Column Width = (hooks_per_row × 28px) + spacing
Word Column Width = remaining_space × word_ratio
```

### Implementation Details

#### Core Files
- `UnifiedSearchModel.swift`: Search logic with mode detection
- `UnifiedSearchView.swift`: Optimized UI with hooks visualization
- `DataManager.swift`: Unified data access for trie, words, and hooks
- `SpanishUtils.swift`: Centralized Spanish text processing utilities

#### Hooks Database
- **Location**: `Resources/scrabble_hooks.sqlite`
- **Generation**: Python script in `Scripts/generate_hooks.py`
- **Content**: 639,293 words with external and internal hooks
- **Structure**: Normalized words with left/right external/internal hook strings

#### Visual Examples
- **"ES" (2 letters, 20 hooks)**: Compact word, 5 rows of 4 hooks each
- **"CHURRULLERO" (11 letters, 1 hook)**: Large word space, minimal hook area
- **Perfect Squares**: All hooks (including "CH", "LL", "RR") fit identically

### Toggle System
- **"Mostrar ganchos"**: Clean toggle without icons
- **Default View**: Standard word list when hooks are disabled
- **Enhanced View**: Full hooks visualization when enabled
- **Mode-Specific**: Only available for anagram and pattern modes