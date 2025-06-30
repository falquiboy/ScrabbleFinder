package com.maslexico.android

import java.util.*

object SpanishUtils {
    
    // MARK: - Digraph Mappings
    private val digraphsToInternal = mapOf(
        "CH" to 'Ç',
        "LL" to 'K', 
        "RR" to 'W'
    )
    
    private val internalToDigraphs = mapOf(
        'Ç' to "CH",
        'K' to "LL",
        'W' to "RR"
    )
    
    // MARK: - Spanish Alphabet Orders
    
    // For ALPHAGRAMS: Vowels first for efficient grouping (CH=Ç, LL=K, RR=W)
    // Orden correcto: vocales + consonantes en orden alfabético español tradicional
    private val alphagramOrder = "AEIOUBCÇDFGHJLKMNÑPQRWSTVXYZ".toCharArray()
    private val alphagramOrderMap: Map<Char, Int> = alphagramOrder.mapIndexed { index, char -> char to index }.toMap()
    
    // For DISPLAY: Traditional Spanish alphabetical order (CH=Ç, LL=K, RR=W) 
    private val displayOrder = "ABCÇDEFGHIJLKMNÑOPQRWSTUVXYZ".toCharArray()
    private val displayOrderMap: Map<Char, Int> = displayOrder.mapIndexed { index, char -> char to index }.toMap()
    
    // Display Spanish alphabet (with natural digraphs)
    private val spanishAlphabet = listOf(
        "A", "B", "C", "CH", "D", "E", "F", "G", "H", "I", "J", "L", "LL", "M", "N", "Ñ", 
        "O", "P", "Q", "R", "RR", "S", "T", "U", "V", "W", "X", "Y", "Z"
    )
    
    /**
     * Converts Spanish digraphs to internal single characters for processing
     * CH -> Ç, LL -> K, RR -> W
     */
    fun normalizeWord(word: String): String {
        var normalized = word.uppercase()
        digraphsToInternal.forEach { (digraph, internal) ->
            normalized = normalized.replace(digraph, internal.toString())
        }
        return normalized
    }
    
    /**
     * Converts internal characters back to Spanish digraphs for display
     * Ç -> CH, K -> LL, W -> RR
     */
    fun denormalizeWord(word: String): String {
        var denormalized = word
        internalToDigraphs.forEach { (internal, digraph) ->
            denormalized = denormalized.replace(internal.toString(), digraph)
        }
        return denormalized
    }
    
    /**
     * Creates an alphagram (sorted characters) for anagram matching
     * Uses vowels-first order for efficient grouping
     */
    fun createAlphagram(letters: String): String {
        val normalized = normalizeWord(letters)
        return normalized.toCharArray()
            .sortedWith { a, b -> 
                val orderA = alphagramOrderMap[a] ?: Int.MAX_VALUE
                val orderB = alphagramOrderMap[b] ?: Int.MAX_VALUE
                orderA.compareTo(orderB)
            }
            .joinToString("")
    }
    
    /**
     * Sorts words according to traditional Spanish alphabetical order (for display)
     */
    fun sortWordsSpanish(words: List<String>): List<String> {
        return words.sortedWith { word1, word2 ->
            val norm1 = normalizeWord(word1)
            val norm2 = normalizeWord(word2)
            
            for (i in 0 until minOf(norm1.length, norm2.length)) {
                val order1 = displayOrderMap[norm1[i]] ?: Int.MAX_VALUE
                val order2 = displayOrderMap[norm2[i]] ?: Int.MAX_VALUE
                
                if (order1 != order2) {
                    return@sortedWith order1.compareTo(order2)
                }
            }
            
            norm1.length.compareTo(norm2.length)
        }
    }
    
    /**
     * Checks if a character is a vowel
     */
    fun isVowel(char: Char): Boolean {
        return char.uppercaseChar() in "AEIOU"
    }
    
    /**
     * Gets Spanish character value for scoring
     */
    fun getCharacterValue(char: Char): Int {
        return when (char.uppercaseChar()) {
            'A', 'E', 'I', 'O', 'U', 'L', 'N', 'R', 'S', 'T' -> 1
            'D', 'G' -> 2
            'C', 'B', 'M', 'P' -> 3
            'F', 'H', 'V', 'Y' -> 4
            'Ç' -> 5  // CH
            'J', 'K', 'Ñ', 'Q', 'W', 'X', 'Z' -> 8  // Including LL and RR
            else -> 0
        }
    }
    
    /**
     * Calculates word score based on character values
     */
    fun calculateWordScore(word: String): Int {
        return normalizeWord(word).sumOf { getCharacterValue(it) }
    }
    
    /**
     * Compares two words using traditional Spanish alphabetical order (for display)
     * Returns: negative if word1 < word2, positive if word1 > word2, zero if equal
     */
    fun compareWordsSpanish(word1: String, word2: String): Int {
        val norm1 = normalizeWord(word1)
        val norm2 = normalizeWord(word2)
        
        for (i in 0 until minOf(norm1.length, norm2.length)) {
            val order1 = displayOrderMap[norm1[i]] ?: Int.MAX_VALUE
            val order2 = displayOrderMap[norm2[i]] ?: Int.MAX_VALUE
            
            if (order1 != order2) {
                return order1.compareTo(order2)
            }
        }
        
        return norm1.length.compareTo(norm2.length)
    }
    
    /**
     * Gets the traditional Spanish alphabetical order position of an internal character
     * Used for sorting wildcard results correctly
     */
    fun getDisplayOrder(char: Char): Int {
        return displayOrderMap[char] ?: Int.MAX_VALUE
    }
    
    /**
     * Test function to verify both Spanish orderings
     * Useful for debugging and verification
     */
    fun testSpanishOrder(): String {
        val testWords = listOf("CASA", "CHARCO", "LLAMADA", "LLAMA", "PERRO", "RRR", "CARRO")
        val sorted = sortWordsSpanish(testWords)
        val testAlphagram = createAlphagram("CASA")
        return """
            Original: $testWords
            Sorted (display): $sorted
            Alphagram order: ${alphagramOrder.joinToString("")}
            Display order: ${displayOrder.joinToString("")}
            CASA alphagram: $testAlphagram
        """.trimIndent()
    }
}