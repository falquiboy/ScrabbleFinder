package com.maslexico.android

/**
 * Simple TrieNode implementation for future trie-based searches
 * Currently using SQLite as primary data source
 */
class TrieNode {
    private val children = mutableMapOf<Char, TrieNode>()
    var isEndOfWord = false
    var word: String? = null
    
    /**
     * Insert a word into the trie
     */
    fun insert(word: String) {
        val normalizedWord = SpanishUtils.normalizeWord(word)
        var current = this
        
        for (char in normalizedWord) {
            current = current.children.getOrPut(char) { TrieNode() }
        }
        
        current.isEndOfWord = true
        current.word = word
    }
    
    /**
     * Search for a word in the trie
     */
    fun search(word: String): Boolean {
        val normalizedWord = SpanishUtils.normalizeWord(word)
        var current = this
        
        for (char in normalizedWord) {
            current = current.children[char] ?: return false
        }
        
        return current.isEndOfWord
    }
    
    /**
     * Find all words that can be formed using the given letters
     */
    fun findAnagrams(letters: String): List<String> {
        val normalizedLetters = SpanishUtils.normalizeWord(letters)
        val letterCount = normalizedLetters.groupingBy { it }.eachCount().toMutableMap()
        val results = mutableListOf<String>()
        
        findAnagramsHelper(this, letterCount, results)
        
        return results.sortedBy { it.length }
    }
    
    private fun findAnagramsHelper(
        node: TrieNode,
        letterCount: MutableMap<Char, Int>,
        results: MutableList<String>
    ) {
        if (node.isEndOfWord && node.word != null) {
            results.add(node.word!!)
        }
        
        for ((char, childNode) in node.children) {
            val count = letterCount[char] ?: 0
            if (count > 0) {
                letterCount[char] = count - 1
                findAnagramsHelper(childNode, letterCount, results)
                letterCount[char] = count
            }
        }
    }
    
    /**
     * Find words matching a pattern with rack constraints
     * Pattern format: dots (.) for wildcards, letters for fixed positions
     * Rack: available letters to use for wildcards
     */
    fun findPatternWords(
        pattern: String, 
        rackLetters: List<Char> = emptyList(),
        rackWildcards: Int = 0,
        fixedLength: Int? = null
    ): List<String> {
        val normalizedPattern = SpanishUtils.normalizeWord(pattern)
        val normalizedRack = rackLetters.map { SpanishUtils.normalizeWord(it.toString()).firstOrNull() ?: it }
        val availableLetters = normalizedRack.groupingBy { it }.eachCount().toMutableMap()
        val results = mutableListOf<String>()
        
        findPatternHelper(
            node = this,
            pattern = normalizedPattern,
            patternIndex = 0,
            availableLetters = availableLetters,
            wildcardCount = rackWildcards,
            fixedLength = fixedLength,
            results = results
        )
        
        return results.sortedWith(compareBy<String> { it.length }.thenBy { it })
    }
    
    private fun findPatternHelper(
        node: TrieNode,
        pattern: String,
        patternIndex: Int,
        availableLetters: MutableMap<Char, Int>,
        wildcardCount: Int,
        fixedLength: Int?,
        results: MutableList<String>
    ) {
        // Check if we've matched the entire pattern
        if (patternIndex >= pattern.length) {
            if (node.isEndOfWord && node.word != null) {
                val wordLength = node.word!!.length
                if (fixedLength == null || wordLength == fixedLength) {
                    results.add(node.word!!)
                }
            }
            return
        }
        
        val currentChar = pattern[patternIndex]
        
        when (currentChar) {
            '.' -> {
                // Wildcard position - try available rack letters first
                for ((rackChar, count) in availableLetters) {
                    if (count > 0 && node.children.containsKey(rackChar)) {
                        availableLetters[rackChar] = count - 1
                        findPatternHelper(
                            node.children[rackChar]!!,
                            pattern,
                            patternIndex + 1,
                            availableLetters,
                            wildcardCount,
                            fixedLength,
                            results
                        )
                        availableLetters[rackChar] = count
                    }
                }
                
                // If we have rack wildcards, try any letter
                if (wildcardCount > 0) {
                    for ((char, childNode) in node.children) {
                        if (!availableLetters.containsKey(char) || availableLetters[char] == 0) {
                            findPatternHelper(
                                childNode,
                                pattern,
                                patternIndex + 1,
                                availableLetters,
                                wildcardCount - 1,
                                fixedLength,
                                results
                            )
                        }
                    }
                }
            }
            
            '*' -> {
                // Asterisk - match any number of characters (including zero)
                // First, try matching zero characters (skip the asterisk)
                findPatternHelper(
                    node,
                    pattern,
                    patternIndex + 1,
                    availableLetters,
                    wildcardCount,
                    fixedLength,
                    results
                )
                
                // Then try matching one or more characters
                for ((char, childNode) in node.children) {
                    val rackCount = availableLetters[char] ?: 0
                    if (rackCount > 0) {
                        availableLetters[char] = rackCount - 1
                        findPatternHelper(
                            childNode,
                            pattern,
                            patternIndex, // Keep same pattern position for asterisk
                            availableLetters,
                            wildcardCount,
                            fixedLength,
                            results
                        )
                        availableLetters[char] = rackCount
                    } else if (wildcardCount > 0) {
                        findPatternHelper(
                            childNode,
                            pattern,
                            patternIndex, // Keep same pattern position for asterisk
                            availableLetters,
                            wildcardCount - 1,
                            fixedLength,
                            results
                        )
                    }
                }
            }
            
            else -> {
                // Fixed character - must match exactly
                val childNode = node.children[currentChar]
                if (childNode != null) {
                    findPatternHelper(
                        childNode,
                        pattern,
                        patternIndex + 1,
                        availableLetters,
                        wildcardCount,
                        fixedLength,
                        results
                    )
                }
            }
        }
    }
    
    /**
     * Get all words stored in the trie
     */
    fun getAllWords(): List<String> {
        val results = mutableListOf<String>()
        getAllWordsHelper(this, results)
        return results
    }
    
    private fun getAllWordsHelper(node: TrieNode, results: MutableList<String>) {
        if (node.isEndOfWord && node.word != null) {
            results.add(node.word!!)
        }
        
        for (childNode in node.children.values) {
            getAllWordsHelper(childNode, results)
        }
    }
}