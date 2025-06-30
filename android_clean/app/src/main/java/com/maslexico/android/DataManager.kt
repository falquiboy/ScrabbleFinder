package com.maslexico.android

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

data class SearchResult(
    val words: List<String>,
    val executionTime: Double,
    val source: String
)

data class WordHooks(
    val word: String,
    val leftExternal: String = "",
    val rightExternal: String = "",
    val leftInternal: String = "",
    val rightInternal: String = ""
) {
    val hasExternalHooks: Boolean
        get() = leftExternal.isNotEmpty() || rightExternal.isNotEmpty()
    
    val hasInternalHooks: Boolean
        get() = leftInternal.isNotEmpty() || rightInternal.isNotEmpty()
    
    val hasAnyHooks: Boolean
        get() = hasExternalHooks || hasInternalHooks
    
    val externalDisplay: String
        get() = leftExternal.lowercase() + word + rightExternal.lowercase()
}

class DataManager private constructor(private val context: Context) {
    
    companion object {
        @Volatile
        private var INSTANCE: DataManager? = null
        
        fun getInstance(context: Context): DataManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: DataManager(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private var wordsDatabase: SQLiteDatabase? = null
    private var hooksDatabase: SQLiteDatabase? = null
    private var trieNode: TrieNode? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val wildcardSearch = WildcardSearch(this)
    
    init {
        initializeDatabases()
    }
    
    private fun initializeDatabases() {
        scope.launch {
            try {
                println("DataManager: Starting database initialization")
                
                // Copy and initialize words database
                val wordsDbFile = copyAssetToInternalStorage("scrabble_words.sqlite", "words.db")
                wordsDatabase = SQLiteDatabase.openDatabase(wordsDbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                println("DataManager: Words database initialized at ${wordsDbFile.absolutePath}")
                
                // Copy and initialize hooks database
                val hooksDbFile = copyAssetToInternalStorage("scrabble_hooks.sqlite", "hooks.db")
                hooksDatabase = SQLiteDatabase.openDatabase(hooksDbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                println("DataManager: Hooks database initialized at ${hooksDbFile.absolutePath}")
                
                // Test database connection
                testDatabaseConnection()
                
            } catch (e: Exception) {
                println("DataManager: Error initializing databases: ${e.message}")
                e.printStackTrace()
            }
        }
    }
    
    private fun testDatabaseConnection() {
        try {
            val cursor = wordsDatabase?.rawQuery("SELECT COUNT(*) FROM words", null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val count = it.getInt(0)
                    println("DataManager: Found $count words in database")
                }
            }
        } catch (e: Exception) {
            println("DataManager: Error testing database: ${e.message}")
        }
    }
    
    private fun copyAssetToInternalStorage(assetName: String, fileName: String): File {
        val file = File(context.filesDir, fileName)
        if (!file.exists()) {
            context.assets.open(assetName).use { inputStream ->
                FileOutputStream(file).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            }
        }
        return file
    }
    
    suspend fun findAnagramsWithWildcards(letters: String): WildcardSearchResult = withContext(Dispatchers.IO) {
        return@withContext wildcardSearch.findAnagramsWithWildcards(letters)
    }
    
    suspend fun generateSubanagrams(baseLetters: String): Map<Int, List<WildcardWord>> = withContext(Dispatchers.IO) {
        return@withContext wildcardSearch.generateSubanagrams(baseLetters)
    }
    
    suspend fun findAnagrams(letters: String): SearchResult = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        val words = mutableListOf<String>()
        
        try {
            println("DataManager: Searching anagrams for '$letters'")
            
            if (wordsDatabase == null) {
                println("DataManager: Words database is null!")
                return@withContext SearchResult(emptyList(), 0.0, "Error: DB not initialized")
            }
            
            val alphagram = SpanishUtils.createAlphagram(letters)
            println("DataManager: Created alphagram '$alphagram' from '$letters'")
            
            val cursor = wordsDatabase?.rawQuery(
                "SELECT word FROM words WHERE alphagram = ? ORDER BY length(word) DESC, word",
                arrayOf(alphagram)
            )
            
            cursor?.use {
                var count = 0
                while (it.moveToNext()) {
                    val word = it.getString(0)
                    words.add(word)
                    count++
                }
                println("DataManager: Found $count words for alphagram '$alphagram'")
            }
            
            // If no results, let's try a simple test query
            if (words.isEmpty()) {
                println("DataManager: No results found, testing database...")
                val testCursor = wordsDatabase?.rawQuery("SELECT word FROM words LIMIT 5", null)
                testCursor?.use {
                    println("DataManager: Sample words from database:")
                    while (it.moveToNext()) {
                        println("  - ${it.getString(0)}")
                    }
                }
            }
            
        } catch (e: Exception) {
            println("DataManager: Error in findAnagrams: ${e.message}")
            e.printStackTrace()
        }
        
        val executionTime = (System.currentTimeMillis() - startTime) / 1000.0
        println("DataManager: Search completed in ${executionTime}s, found ${words.size} words")
        SearchResult(words, executionTime, "SQLite")
    }
    
    suspend fun findHooks(word: String): WordHooks? = withContext(Dispatchers.IO) {
        try {
            val normalizedWord = SpanishUtils.normalizeWord(word)
            val cursor = hooksDatabase?.rawQuery(
                "SELECT left_external, right_external, left_internal, right_internal FROM word_hooks WHERE word = ?",
                arrayOf(normalizedWord)
            )
            
            cursor?.use {
                if (it.moveToFirst()) {
                    val leftExt = it.getString(0) ?: ""
                    val rightExt = it.getString(1) ?: ""
                    val leftInt = it.getString(2) ?: ""
                    val rightInt = it.getString(3) ?: ""
                    
                    
                    return@withContext WordHooks(
                        word = word,
                        leftExternal = leftExt,
                        rightExternal = rightExt,
                        leftInternal = leftInt,
                        rightInternal = rightInt
                    )
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext null
    }
    
    suspend fun validateWord(word: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val normalizedWord = SpanishUtils.normalizeWord(word)
            val cursor = wordsDatabase?.rawQuery(
                "SELECT 1 FROM words WHERE word = ? LIMIT 1",
                arrayOf(normalizedWord)
            )
            
            cursor?.use {
                return@withContext it.moveToFirst()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext false
    }
    
    /**
     * Search for words matching a pattern with filters
     */
    suspend fun findPatternWords(parsedPattern: ParsedPattern): Map<Int, List<String>> = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        
        try {
            println("DataManager: Starting pattern search for: ${parsedPattern.toDebugString()}")
            
            if (wordsDatabase == null) {
                println("DataManager: Words database is null!")
                return@withContext emptyMap()
            }
            
            // Use SQL-based pattern search for efficiency
            val results = findPatternWordsSql(parsedPattern)
            
            val executionTime = (System.currentTimeMillis() - startTime) / 1000.0
            println("DataManager: Pattern search completed in ${executionTime}s, found ${results.values.sumOf { it.size }} words")
            
            return@withContext results
            
        } catch (e: Exception) {
            println("DataManager: Error in findPatternWords: ${e.message}")
            e.printStackTrace()
            return@withContext emptyMap()
        }
    }
    
    /**
     * SQL-based pattern search implementation for better performance
     */
    private suspend fun findPatternWordsSql(parsedPattern: ParsedPattern): Map<Int, List<String>> {
        val results = mutableMapOf<Int, MutableList<String>>()
        
        // Build SQL query based on pattern
        val sqlQuery = buildPatternSqlQuery(parsedPattern)
        val queryParams = buildPatternSqlParams(parsedPattern)
        
        println("DataManager: Executing SQL query: $sqlQuery")
        println("DataManager: Query params: ${queryParams.contentToString()}")
        println("DataManager: Pattern details - fixedLength: ${parsedPattern.fixedLength}, pattern: '${parsedPattern.pattern}'")
        
        // Debug: test if length constraint works at all
        if (parsedPattern.fixedLength != null && parsedPattern.pattern.isEmpty()) {
            // Try multiple test queries to debug
            println("DataManager: Testing different length queries...")
            
            // Test 1: Direct number
            val testCursor1 = wordsDatabase?.rawQuery("SELECT COUNT(*) FROM words WHERE length(word) = 4", null)
            testCursor1?.use {
                if (it.moveToFirst()) {
                    val count = it.getInt(0)
                    println("DataManager: Direct query 'length(word) = 4' found $count words")
                }
            }
            
            // Test 2: With parameter
            val testCursor2 = wordsDatabase?.rawQuery("SELECT COUNT(*) FROM words WHERE length(word) = ?", arrayOf("4"))
            testCursor2?.use {
                if (it.moveToFirst()) {
                    val count = it.getInt(0)
                    println("DataManager: Parameterized query 'length(word) = ?' with '4' found $count words")
                }
            }
            
            // Test 3: With integer parameter
            val testCursor3 = wordsDatabase?.rawQuery("SELECT COUNT(*) FROM words WHERE length(word) = ?", arrayOf(4.toString()))
            testCursor3?.use {
                if (it.moveToFirst()) {
                    val count = it.getInt(0)
                    println("DataManager: Integer parameter query found $count words")
                }
            }
        }
        
        val cursor = wordsDatabase?.rawQuery(sqlQuery, queryParams)
        
        cursor?.use {
            var totalRows = 0
            var filteredRows = 0
            while (it.moveToNext()) {
                totalRows++
                val word = it.getString(0)
                val wordLength = it.getInt(1)
                
                // Apply include/exclude filters
                if (passesFilters(word, parsedPattern)) {
                    filteredRows++
                    results.getOrPut(wordLength) { mutableListOf() }.add(word)
                } else if (totalRows <= 5) {
                    // Debug first few rejected words
                    println("DataManager: Rejected word '$word' (requiresRack=${parsedPattern.requiresRack}, hasFilters=${parsedPattern.hasFilters})")
                }
            }
            println("DataManager: SQL returned $totalRows rows, $filteredRows passed filters")
        }
        
        // Sort results within each length group
        results.forEach { (_, words) ->
            words.sortWith { word1, word2 ->
                SpanishUtils.compareWordsSpanish(word1, word2)
            }
        }
        
        return results.toMap()
    }
    
    /**
     * Build SQL query for pattern matching
     */
    private fun buildPatternSqlQuery(parsedPattern: ParsedPattern): String {
        val baseQuery = StringBuilder("SELECT word, length(word) as word_length FROM words WHERE 1=1")
        
        // Add pattern constraint
        if (parsedPattern.pattern.isNotEmpty()) {
            when {
                parsedPattern.pattern == "*" -> {
                    // Asterisk alone - no additional constraint needed
                }
                parsedPattern.pattern.contains("@") || parsedPattern.pattern.contains("&") -> {
                    // Patterns with @ or & need to be handled in code, not SQL
                    // Only add length constraint if we can determine it
                    if (!parsedPattern.pattern.contains("*") && !parsedPattern.pattern.contains(".")) {
                        baseQuery.append(" AND length(word) = ${parsedPattern.pattern.length}")
                    }
                }
                parsedPattern.pattern.contains("*") -> {
                    // Pattern with asterisk - use LIKE
                    baseQuery.append(" AND word LIKE ?")
                }
                parsedPattern.pattern.contains(".") -> {
                    // Pattern with dots - use LIKE
                    baseQuery.append(" AND word LIKE ?")
                }
                else -> {
                    // Exact pattern - use direct match or LIKE for flexibility
                    baseQuery.append(" AND word LIKE ?")
                }
            }
        }
        // If pattern is empty but we have other constraints (length, rack), that's OK
        
        // Add length constraint - use precomputed length column
        if (parsedPattern.fixedLength != null) {
            baseQuery.append(" AND length = ?")
        }
        
        // Add rack constraint if specified
        if (parsedPattern.requiresRack) {
            // For rack constraints, we'll filter the results in code
            // since SQL regex is limited for this complex logic
        }
        
        baseQuery.append(" ORDER BY length(word) DESC, word")
        
        return baseQuery.toString()
    }
    
    /**
     * Build SQL query parameters
     */
    private fun buildPatternSqlParams(parsedPattern: ParsedPattern): Array<String> {
        val params = mutableListOf<String>()
        
        // Add pattern parameter
        if (parsedPattern.pattern.isNotEmpty()) {
            when {
                parsedPattern.pattern == "*" -> {
                    // No parameter needed for asterisk alone
                }
                parsedPattern.pattern.contains("@") || parsedPattern.pattern.contains("&") -> {
                    // No SQL parameter needed for @ and & patterns - handled in code
                }
                else -> {
                    // Convert pattern to SQL LIKE pattern
                    val sqlPattern = convertPatternToSql(parsedPattern.pattern)
                    params.add(sqlPattern)
                }
            }
        }
        
        // Add length parameter  
        if (parsedPattern.fixedLength != null) {
            params.add(parsedPattern.fixedLength.toString())
        }
        
        return params.toTypedArray()
    }
    
    /**
     * Convert pattern syntax to SQL LIKE pattern
     */
    private fun convertPatternToSql(pattern: String): String {
        var sqlPattern = SpanishUtils.normalizeWord(pattern)
        
        // Convert pattern wildcards to SQL wildcards
        sqlPattern = sqlPattern.replace(".", "_")  // Single character wildcard
        sqlPattern = sqlPattern.replace("*", "%")   // Multiple character wildcard
        
        // @ and & symbols cannot be converted to SQL LIKE directly
        // They represent character classes (vowels/consonants) which will be handled in code filtering
        sqlPattern = sqlPattern.replace("@", "_")  // Treat as single char wildcard for SQL
        sqlPattern = sqlPattern.replace("&", "_")  // Treat as single char wildcard for SQL
        
        return sqlPattern
    }
    
    /**
     * Vocales españolas (incluyendo acentuadas)
     */
    private val SPANISH_VOWELS = setOf('A', 'E', 'I', 'O', 'U', 'Ä', 'Ë', 'Ï', 'Ö', 'Ü')
    
    /**
     * Consonantes españolas (incluyendo dígrafos normalizados)
     */
    private val SPANISH_CONSONANTS = setOf('B', 'C', 'D', 'F', 'G', 'H', 'J', 'L', 'M', 'N', 'Ñ', 'P', 'Q', 'R', 'S', 'T', 'V', 'X', 'Y', 'Z', 'Ç', 'K', 'W')
    
    /**
     * Verifica si un caracter es vocal española
     */
    private fun isSpanishVowel(char: Char): Boolean = char.uppercaseChar() in SPANISH_VOWELS
    
    /**
     * Verifica si un caracter es consonante española  
     */
    private fun isSpanishConsonant(char: Char): Boolean = char.uppercaseChar() in SPANISH_CONSONANTS
    
    /**
     * Cuenta vocales en una palabra
     */
    private fun countVowels(word: String): Int = word.count { isSpanishVowel(it) }
    
    /**
     * Cuenta consonantes en una palabra
     */
    private fun countConsonants(word: String): Int = word.count { isSpanishConsonant(it) }
    
    /**
     * Cuenta ocurrencias de una letra específica en una palabra
     */
    private fun countLetter(word: String, letter: Char): Int = word.count { it.uppercaseChar() == letter.uppercaseChar() }
    
    /**
     * Cuenta letras individuales L en una palabra SIN NORMALIZAR (antes de convertir LL a K)
     */
    private fun countIndividualL(originalWord: String): Int {
        // Contar todas las L que NO están en dígrafo LL
        var count = 0
        var i = 0
        while (i < originalWord.length) {
            val char = originalWord[i].uppercaseChar()
            if (char == 'L') {
                // Verificar si es parte de dígrafo LL
                if (i + 1 < originalWord.length && originalWord[i + 1].uppercaseChar() == 'L') {
                    // Es dígrafo LL, saltar ambas letras
                    i += 2
                } else {
                    // Es L individual
                    count++
                    i++
                }
            } else {
                i++
            }
        }
        return count
    }
    
    /**
     * Cuenta letras individuales R en una palabra SIN NORMALIZAR (antes de convertir RR a W)
     */
    private fun countIndividualR(originalWord: String): Int {
        // Contar todas las R que NO están en dígrafo RR
        var count = 0
        var i = 0
        while (i < originalWord.length) {
            val char = originalWord[i].uppercaseChar()
            if (char == 'R') {
                // Verificar si es parte de dígrafo RR
                if (i + 1 < originalWord.length && originalWord[i + 1].uppercaseChar() == 'R') {
                    // Es dígrafo RR, saltar ambas letras
                    i += 2
                } else {
                    // Es R individual
                    count++
                    i++
                }
            } else {
                i++
            }
        }
        return count
    }
    
    /**
     * Cuenta dígrafos LL (normalizados como K) en una palabra
     */
    private fun countDigraphLL(word: String): Int = word.count { it.uppercaseChar() == 'K' }
    
    /**
     * Cuenta dígrafos RR (normalizados como W) en una palabra
     */
    private fun countDigraphRR(word: String): Int = word.count { it.uppercaseChar() == 'W' }
    
    /**
     * Verifica si una palabra coincide completamente con un patrón (incluyendo @ y &)
     */
    private fun matchesAdvancedPattern(word: String, pattern: String): Boolean {
        // Si no hay patrón específico, no hay restricciones de posición
        if (pattern.isEmpty() || pattern == "*") {
            return true
        }
        
        // Para patrones con *, necesitamos lógica más compleja
        if (pattern.contains('*')) {
            return matchesWildcardPattern(word, pattern)
        }
        
        // Para patrones de longitud fija
        if (word.length != pattern.length) {
            return false
        }
        
        for (i in pattern.indices) {
            val patternChar = pattern[i]
            val wordChar = word[i]
            
            when (patternChar) {
                '@' -> {
                    if (!isSpanishVowel(wordChar)) {
                        return false
                    }
                }
                '&' -> {
                    if (!isSpanishConsonant(wordChar)) {
                        return false
                    }
                }
                '.', '_' -> {
                    // Wildcard, cualquier caracter es válido
                    continue
                }
                else -> {
                    // Caracter específico debe coincidir
                    if (wordChar.uppercaseChar() != patternChar.uppercaseChar()) {
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    /**
     * Maneja patrones con asterisco (*) de manera más sofisticada
     */
    private fun matchesWildcardPattern(word: String, pattern: String): Boolean {
        // Convertir patrón a regex, manejando @ y & correctamente
        var regexPattern = pattern
            .replace(".", "\\w")  // Cualquier letra
            .replace("*", "\\w*")  // Cero o más letras
        
        // Para @ y &, necesitamos verificación manual ya que regex no puede manejar clases personalizadas fácilmente
        if (pattern.contains('@') || pattern.contains('&')) {
            return matchesComplexWildcardPattern(word, pattern)
        }
        
        val regex = Regex("^$regexPattern$", RegexOption.IGNORE_CASE)
        return regex.matches(word)
    }
    
    /**
     * Maneja patrones complejos con asterisco y símbolos @ &
     */
    private fun matchesComplexWildcardPattern(word: String, pattern: String): Boolean {
        // Implementación simplificada para patrones comunes
        when {
            pattern.startsWith("*") && pattern.endsWith("*") -> {
                // Patrón como "*@*" - verificar que contenga al menos una vocal
                val middle = pattern.substring(1, pattern.length - 1)
                return containsPatternSequence(word, middle)
            }
            pattern.startsWith("*") -> {
                // Patrón como "*@&" - verificar terminación
                val suffix = pattern.substring(1)
                return word.length >= suffix.length && 
                       matchesAdvancedPattern(word.substring(word.length - suffix.length), suffix)
            }
            pattern.endsWith("*") -> {
                // Patrón como "@&*" - verificar inicio
                val prefix = pattern.substring(0, pattern.length - 1)
                return word.length >= prefix.length && 
                       matchesAdvancedPattern(word.substring(0, prefix.length), prefix)
            }
            else -> {
                // Casos más complejos - por ahora delegamos a coincidencia de longitud
                return true
            }
        }
    }
    
    /**
     * Verifica si una palabra contiene una secuencia específica
     */
    private fun containsPatternSequence(word: String, sequence: String): Boolean {
        if (sequence.isEmpty()) return true
        
        for (i in 0..word.length - sequence.length) {
            val substring = word.substring(i, i + sequence.length)
            if (matchesAdvancedPattern(substring, sequence)) {
                return true
            }
        }
        return false
    }
    
    /**
     * Check if word passes include/exclude filters and rack constraints
     */
    private fun passesFilters(word: String, parsedPattern: ParsedPattern): Boolean {
        val normalizedWord = SpanishUtils.normalizeWord(word)
        
        // ALWAYS check pattern matching if pattern exists (including @ and & symbols)
        if (parsedPattern.pattern.isNotEmpty() && parsedPattern.pattern != "*") {
            if (!matchesAdvancedPattern(normalizedWord, parsedPattern.pattern)) {
                return false
            }
        }
        
        // Check include letters
        for (letter in parsedPattern.includeLetters) {
            if (!normalizedWord.contains(letter)) {
                return false
            }
        }
        
        // Check exclude letters
        for (letter in parsedPattern.excludeLetters) {
            if (normalizedWord.contains(letter)) {
                return false
            }
        }
        
        // Check vowel count constraints
        val vowelCount = countVowels(normalizedWord)
        if (parsedPattern.includeVowelCount != null && vowelCount < parsedPattern.includeVowelCount) {
            return false
        }
        if (parsedPattern.excludeVowelCount != null && vowelCount >= parsedPattern.excludeVowelCount) {
            return false
        }
        
        // Check consonant count constraints
        val consonantCount = countConsonants(normalizedWord)
        if (parsedPattern.includeConsonantCount != null && consonantCount < parsedPattern.includeConsonantCount) {
            return false
        }
        if (parsedPattern.excludeConsonantCount != null && consonantCount >= parsedPattern.excludeConsonantCount) {
            return false
        }
        
        // Check specific letter count constraints (include)
        for ((letter, requiredCount) in parsedPattern.includeLetterCounts) {
            val actualCount = when (letter.uppercaseChar()) {
                'L' -> countIndividualL(word) // Usar palabra original para contar L individuales
                'R' -> countIndividualR(word) // Usar palabra original para contar R individuales
                'K' -> countDigraphLL(normalizedWord) // Contar dígrafos LL (normalizados como K)
                'W' -> countDigraphRR(normalizedWord) // Contar dígrafos RR (normalizados como W)
                else -> countLetter(normalizedWord, letter) // Conteo normal para otras letras
            }
            
            
            if (actualCount < requiredCount) {
                return false
            }
        }
        
        // Check specific letter count constraints (exclude)
        for ((letter, maxCount) in parsedPattern.excludeLetterCounts) {
            val actualCount = when (letter.uppercaseChar()) {
                'L' -> countIndividualL(word) // Usar palabra original para contar L individuales
                'R' -> countIndividualR(word) // Usar palabra original para contar R individuales
                'K' -> countDigraphLL(normalizedWord) // Contar dígrafos LL (normalizados como K)
                'W' -> countDigraphRR(normalizedWord) // Contar dígrafos RR (normalizados como W)
                else -> countLetter(normalizedWord, letter) // Conteo normal para otras letras
            }
            if (actualCount >= maxCount) {
                return false
            }
        }
        
        // Check rack constraints if specified
        if (parsedPattern.requiresRack) {
            return passesRackConstraints(normalizedWord, parsedPattern)
        }
        
        return true
    }
    
    /**
     * Check if word can be formed with the given rack
     */
    private fun passesRackConstraints(word: String, parsedPattern: ParsedPattern): Boolean {
        // Get fixed letters from pattern (non-wildcard positions)
        val fixedLetters = getFixedLettersFromPattern(parsedPattern.pattern)
        
        // Count available letters from rack
        val availableLetters = parsedPattern.rackLetters.groupingBy { it }.eachCount().toMutableMap()
        
        // Add wildcards as available "any letter" slots
        var availableWildcards = parsedPattern.rackWildcards
        
        // Check each character in the word
        for (char in word) {
            if (char in fixedLetters) {
                // This character is fixed by the pattern, no rack letter needed
                continue
            }
            
            val availableCount = availableLetters[char] ?: 0
            if (availableCount > 0) {
                // Use a rack letter
                availableLetters[char] = availableCount - 1
            } else if (availableWildcards > 0) {
                // Use a wildcard
                availableWildcards--
            } else {
                // Can't form this word with available rack
                return false
            }
        }
        
        return true
    }
    
    /**
     * Extract fixed letters from pattern (letters that are not wildcards)
     */
    private fun getFixedLettersFromPattern(pattern: String): Set<Char> {
        return pattern.filter { it != '.' && it != '*' && it != '@' && it != '&' }.toSet()
    }
    
    fun cleanup() {
        scope.cancel()
        wordsDatabase?.close()
        hooksDatabase?.close()
    }
}