package com.maslexico.android

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Enhanced search result that supports wildcards and extra letter searches
 */
data class WildcardSearchResult(
    val exactWords: List<WildcardWord>,
    val extraLetterWords: List<WildcardWord>,
    val subanagrams: Map<Int, List<WildcardWord>> = emptyMap(), // Grouped by length
    val executionTime: Double,
    val source: String,
    val query: String,
    val wildcardCount: Int = 0,
    val possibleWildcardLetters: Set<Char> = emptySet(), // Letters that wildcards can represent
    val possibleExtraLetters: Set<Char> = emptySet() // Letters that can be added for extra letter words
) {
    // Legacy compatibility
    val words: List<WildcardWord> get() = exactWords
}

/**
 * Word with wildcard and extra letter information
 */
data class WildcardWord(
    val word: String,
    val wildcardLetters: List<Char> = emptyList(), // Letters that came from wildcards
    val extraLetters: List<Char> = emptyList(), // Letters that are additions to the base rack
    val hooks: WordHooks? = null
) {
    // All letters that should be highlighted in red
    val highlightedLetters: List<Char> get() = wildcardLetters + extraLetters
    
    // Get positions of letters that should be highlighted (0-indexed)
    // Only highlights the FIRST instance of repeated additional/wildcard letters
    fun getHighlightedPositions(baseLetters: String): Set<Int> {
        val positions = mutableSetOf<Int>()
        val normalizedWord = SpanishUtils.normalizeWord(word)
        val normalizedBase = SpanishUtils.normalizeWord(baseLetters)
        
        // Create a mutable copy of base letters to track usage
        val availableBaseLetters = normalizedBase.toMutableList()
        
        // Track which additional letters we've already highlighted (first instance only)
        val highlightedAdditionalLetters = mutableSetOf<Char>()
        
        // For each position in the word, check if it should be highlighted
        for (i in normalizedWord.indices) {
            val char = normalizedWord[i]
            
            // If we can use a base letter, use it (don't highlight)
            if (availableBaseLetters.remove(char)) {
                continue
            }
            
            // This is an additional letter (wildcard or extra)
            // Only highlight if we haven't highlighted this letter before
            if (char !in highlightedAdditionalLetters) {
                positions.add(i)
                highlightedAdditionalLetters.add(char)
            }
            // If we've already highlighted this letter, don't highlight again
            // This allows internal hooks to work on subsequent instances
        }
        
        return positions
    }
}

/**
 * Wildcard search engine - Android-native implementation
 * More elegant and efficient than iOS version
 */
class WildcardSearch(private val dataManager: DataManager) {
    
    companion object {
        const val MAX_WILDCARDS = 2
        // Spanish alphabet for wildcard generation (vowels first for efficiency: CH=Ç, LL=K, RR=W)
        private val SPANISH_ALPHABET = "AEIOUBNÑPCÇDFGHJLKMNPQRWSTVXYZ".toCharArray()
    }
    
    /**
     * Enhanced anagram search with wildcard support
     */
    suspend fun findAnagramsWithWildcards(query: String): WildcardSearchResult = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        val normalizedQuery = SpanishUtils.normalizeWord(query.trim())
        
        val wildcardCount = normalizedQuery.count { it == '?' }
        
        if (wildcardCount == 0) {
            // No wildcards - use standard search + extra letter search
            val standardResult = dataManager.findAnagrams(query)
            val exactWords = standardResult.words.map { WildcardWord(it) }
            
            val (extraWords, extraLetters) = performExtraLetterSearch(normalizedQuery)
            
            return@withContext WildcardSearchResult(
                exactWords = exactWords,
                extraLetterWords = extraWords,
                subanagrams = emptyMap(), // Will be generated when needed
                executionTime = standardResult.executionTime,
                source = standardResult.source,
                query = query,
                wildcardCount = 0,
                possibleExtraLetters = extraLetters
            )
        }
        
        if (wildcardCount > MAX_WILDCARDS) {
            return@withContext WildcardSearchResult(
                exactWords = emptyList(),
                extraLetterWords = emptyList(),
                subanagrams = emptyMap(),
                executionTime = 0.0,
                source = "Error",
                query = query,
                wildcardCount = wildcardCount
            )
        }
        
        // Wildcard search
        val (exactResults, possibleWildcardLetters) = performWildcardSearch(normalizedQuery, wildcardCount)
        
        // Extra letter search with wildcards
        val (extraResults, possibleExtraLetters) = performExtraLetterSearchWithWildcards(normalizedQuery, wildcardCount)
        
        val executionTime = (System.currentTimeMillis() - startTime) / 1000.0
        
        WildcardSearchResult(
            exactWords = exactResults,
            extraLetterWords = extraResults,
            subanagrams = emptyMap(), // Will be generated when needed
            executionTime = executionTime,
            source = "SQLite+Wildcards",
            query = query,
            wildcardCount = wildcardCount,
            possibleWildcardLetters = possibleWildcardLetters,
            possibleExtraLetters = possibleExtraLetters
        )
    }
    
    /**
     * Core wildcard algorithm - generates combinations efficiently
     */
    private suspend fun performWildcardSearch(normalizedQuery: String, wildcardCount: Int): Pair<List<WildcardWord>, Set<Char>> {
        val baseLetters = normalizedQuery.replace("?", "")
        val allResults = mutableSetOf<WildcardWord>()
        val possibleWildcardLetters = mutableSetOf<Char>()
        
        // Generate all possible wildcard combinations
        val combinations = generateWildcardCombinations(wildcardCount)
        
        combinations.forEach { wildcardLetters ->
            val searchQuery = baseLetters + wildcardLetters.joinToString("")
            val standardResult = dataManager.findAnagrams(searchQuery)
            
            // Filter to only include words that actually use the wildcard letters
            val filteredWords = filterWildcardWords(standardResult.words, baseLetters, wildcardLetters)
            
            if (filteredWords.isNotEmpty()) {
                allResults.addAll(filteredWords)
                possibleWildcardLetters.addAll(wildcardLetters)
            }
        }
        
        // Sort by wildcard letters (traditional Spanish order), then by word length (longest first), then Spanish alphabetically
        val sortedResults = allResults.sortedWith(
            compareBy<WildcardWord> { word ->
                // Primary sort: first wildcard letter in traditional Spanish order
                word.wildcardLetters.minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
            }.thenBy { word ->
                // Secondary sort: second wildcard letter in traditional Spanish order (if exists)
                if (word.wildcardLetters.size > 1) {
                    word.wildcardLetters.drop(1).minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
                } else Int.MAX_VALUE
            }.thenBy { -it.word.length } // Tertiary: word length (longest first)
            .thenComparator { word1, word2 -> 
                // Finally: Spanish alphabetical order
                SpanishUtils.compareWordsSpanish(word1.word, word2.word)
            }
        )
        
        return Pair(sortedResults, possibleWildcardLetters)
    }
    
    /**
     * Efficient wildcard combination generation
     * Uses strategic letter prioritization
     */
    private fun generateWildcardCombinations(wildcardCount: Int): List<List<Char>> {
        return when (wildcardCount) {
            1 -> SPANISH_ALPHABET.map { listOf(it) }
            2 -> {
                val combinations = mutableListOf<List<Char>>()
                SPANISH_ALPHABET.forEach { first ->
                    SPANISH_ALPHABET.forEach { second ->
                        combinations.add(listOf(first, second))
                    }
                }
                combinations
            }
            else -> emptyList()
        }
    }
    
    /**
     * Filters words to ensure they actually need the wildcard letters
     * This prevents showing words that could be made without wildcards
     */
    private suspend fun filterWildcardWords(words: List<String>, baseLetters: String, wildcardLetters: List<Char>): List<WildcardWord> {
        return words.mapNotNull { word ->
            val normalizedWord = SpanishUtils.normalizeWord(word)
            val usedWildcardLetters = findUsedWildcardLetters(normalizedWord, baseLetters, wildcardLetters)
            
            if (usedWildcardLetters.isNotEmpty()) {
                WildcardWord(
                    word = word,
                    wildcardLetters = usedWildcardLetters
                )
            } else null
        }
    }
    
    /**
     * Determines which wildcard letters were actually used in forming the word
     */
    private fun findUsedWildcardLetters(word: String, baseLetters: String, wildcardLetters: List<Char>): List<Char> {
        val wordChars = word.toMutableList()
        val baseChars = baseLetters.toMutableList()
        
        // Remove base letters from word
        baseChars.forEach { char ->
            wordChars.remove(char)
        }
        
        // Remaining letters must come from wildcards
        val usedWildcards = mutableListOf<Char>()
        val availableWildcards = wildcardLetters.toMutableList()
        
        wordChars.forEach { char ->
            if (availableWildcards.remove(char)) {
                usedWildcards.add(char)
            }
        }
        
        return usedWildcards
    }
    
    /**
     * Performs extra letter search (no wildcards)
     */
    private suspend fun performExtraLetterSearch(baseLetters: String): Pair<List<WildcardWord>, Set<Char>> {
        val allResults = mutableSetOf<WildcardWord>()
        val possibleExtraLetters = mutableSetOf<Char>()
        
        // Try each letter of the Spanish alphabet as the extra letter
        SPANISH_ALPHABET.forEach { extraLetter ->
            val searchQuery = baseLetters + extraLetter
            val standardResult = dataManager.findAnagrams(searchQuery)
            
            // Filter to only include words that actually need the extra letter
            val filteredWords = filterExtraLetterWords(standardResult.words, baseLetters, extraLetter)
            
            if (filteredWords.isNotEmpty()) {
                allResults.addAll(filteredWords)
                possibleExtraLetters.add(extraLetter)
            }
        }
        
        // Sort by extra letter alphabetically, then by word length, then Spanish alphabetically
        val sortedResults = allResults.sortedWith(
            compareBy<WildcardWord> { word ->
                // Use traditional Spanish order for extra letters
                word.extraLetters.minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
            }.thenBy { -it.word.length }
            .thenComparator { word1, word2 -> 
                // Spanish alphabetical order
                SpanishUtils.compareWordsSpanish(word1.word, word2.word)
            }
        )
        
        return Pair(sortedResults, possibleExtraLetters)
    }
    
    /**
     * Performs extra letter search with wildcards
     */
    private suspend fun performExtraLetterSearchWithWildcards(normalizedQuery: String, wildcardCount: Int): Pair<List<WildcardWord>, Set<Char>> {
        val baseLetters = normalizedQuery.replace("?", "")
        val allResults = mutableSetOf<WildcardWord>()
        val possibleExtraLetters = mutableSetOf<Char>()
        
        // Generate wildcard combinations
        val wildcardCombinations = generateWildcardCombinations(wildcardCount)
        
        // For each wildcard combination, try adding each extra letter
        wildcardCombinations.forEach { wildcardLetters ->
            SPANISH_ALPHABET.forEach { extraLetter ->
                val searchQuery = baseLetters + wildcardLetters.joinToString("") + extraLetter
                val standardResult = dataManager.findAnagrams(searchQuery)
                
                // Filter words that use both wildcards and the extra letter
                val filteredWords = filterWildcardAndExtraLetterWords(
                    standardResult.words, 
                    baseLetters, 
                    wildcardLetters, 
                    extraLetter
                )
                
                if (filteredWords.isNotEmpty()) {
                    allResults.addAll(filteredWords)
                    possibleExtraLetters.add(extraLetter)
                }
            }
        }
        
        // Sort by wildcards first, then extra letter, then length, then Spanish alphabetically
        val sortedResults = allResults.sortedWith(
            compareBy<WildcardWord> { word ->
                // First wildcard in traditional Spanish order
                word.wildcardLetters.minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
            }.thenBy { word ->
                // Second wildcard in traditional Spanish order (if exists)
                if (word.wildcardLetters.size > 1) {
                    word.wildcardLetters.drop(1).minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
                } else Int.MAX_VALUE
            }.thenBy { word ->
                // Extra letter in traditional Spanish order
                word.extraLetters.minOfOrNull { SpanishUtils.getDisplayOrder(it) } ?: Int.MAX_VALUE
            }.thenBy { -it.word.length }
            .thenComparator { word1, word2 -> 
                // Spanish alphabetical order
                SpanishUtils.compareWordsSpanish(word1.word, word2.word)
            }
        )
        
        return Pair(sortedResults, possibleExtraLetters)
    }
    
    /**
     * Filters words to ensure they actually need the extra letter
     */
    private suspend fun filterExtraLetterWords(words: List<String>, baseLetters: String, extraLetter: Char): List<WildcardWord> {
        return words.mapNotNull { word ->
            val normalizedWord = SpanishUtils.normalizeWord(word)
            if (wordUsesExtraLetter(normalizedWord, baseLetters, extraLetter)) {
                WildcardWord(
                    word = word,
                    extraLetters = listOf(extraLetter)
                )
            } else null
        }
    }
    
    /**
     * Filters words for wildcard + extra letter combinations
     */
    private suspend fun filterWildcardAndExtraLetterWords(
        words: List<String>, 
        baseLetters: String, 
        wildcardLetters: List<Char>, 
        extraLetter: Char
    ): List<WildcardWord> {
        return words.mapNotNull { word ->
            val normalizedWord = SpanishUtils.normalizeWord(word)
            val usedWildcardLetters = findUsedWildcardLetters(normalizedWord, baseLetters, wildcardLetters)
            
            if (usedWildcardLetters.isNotEmpty() && wordUsesExtraLetter(normalizedWord, baseLetters + wildcardLetters.joinToString(""), extraLetter)) {
                WildcardWord(
                    word = word,
                    wildcardLetters = usedWildcardLetters,
                    extraLetters = listOf(extraLetter)
                )
            } else null
        }
    }
    
    /**
     * Checks if a word actually uses the extra letter
     */
    private fun wordUsesExtraLetter(word: String, baseLetters: String, extraLetter: Char): Boolean {
        val wordChars = word.toMutableList()
        val availableChars = baseLetters.toMutableList()
        
        // Remove available letters from word
        availableChars.forEach { char ->
            wordChars.remove(char)
        }
        
        // Check if the extra letter is used and needed
        return wordChars.remove(extraLetter) && wordChars.isEmpty()
    }
    
    /**
     * Quick validation for wildcard queries
     */
    fun isValidWildcardQuery(query: String): Boolean {
        val wildcardCount = query.count { it == '?' }
        return wildcardCount <= MAX_WILDCARDS
    }
    
    /**
     * Generates subanagrams from the base letters (ignoring wildcards)
     * Groups by length and sorts alphabetically
     */
    suspend fun generateSubanagrams(baseLetters: String): Map<Int, List<WildcardWord>> = withContext(Dispatchers.IO) {
        val normalizedBase = SpanishUtils.normalizeWord(baseLetters.replace("?", ""))
        if (normalizedBase.length < 2) return@withContext emptyMap()
        
        val subanagramsByLength = mutableMapOf<Int, MutableList<WildcardWord>>()
        
        // Generate all possible combinations of different lengths
        for (length in 2 until normalizedBase.length) {
            val combinations = generateCombinations(normalizedBase, length)
            
            combinations.forEach { combination ->
                val searchResult = dataManager.findAnagrams(combination)
                val words = searchResult.words.map { WildcardWord(it) }
                
                if (words.isNotEmpty()) {
                    subanagramsByLength.getOrPut(length) { mutableListOf() }.addAll(words)
                }
            }
        }
        
        // Sort each length group alphabetically
        subanagramsByLength.forEach { (_, words) ->
            words.sortWith { word1, word2 -> 
                SpanishUtils.compareWordsSpanish(word1.word, word2.word)
            }
        }
        
        return@withContext subanagramsByLength.toMap()
    }
    
    /**
     * Generates all unique combinations of a given length from the input letters
     */
    private fun generateCombinations(letters: String, length: Int): Set<String> {
        if (length > letters.length) return emptySet()
        if (length == 0) return setOf("")
        
        val result = mutableSetOf<String>()
        
        fun backtrack(current: String, remaining: String, needed: Int) {
            if (needed == 0) {
                // Create alphagram for this combination
                result.add(SpanishUtils.createAlphagram(current))
                return
            }
            
            val usedChars = mutableSetOf<Char>()
            for (i in remaining.indices) {
                val char = remaining[i]
                if (char in usedChars) continue
                usedChars.add(char)
                
                val newRemaining = remaining.removeRange(i, i + 1)
                backtrack(current + char, newRemaining, needed - 1)
            }
        }
        
        backtrack("", letters, length)
        return result
    }
}