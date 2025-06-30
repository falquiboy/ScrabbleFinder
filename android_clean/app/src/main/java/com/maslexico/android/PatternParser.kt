package com.maslexico.android

import java.util.regex.Pattern

/**
 * Parser para sintaxis de búsqueda por patrón basado en análisis de Swift iOS
 * Sintaxis: [patrón],[restricciones]:[longitud]
 * 
 * Ejemplos:
 * - "C.SA" -> patrón simple
 * - "*+AEIOU" -> patrón con restricción de inclusión
 * - "*.+EI-J:6" -> patrón completo con inclusión, exclusión y longitud
 * - "C.?,AER?" -> patrón con rack de wildcards
 */
data class ParsedPattern(
    val pattern: String = "",
    val rackLetters: List<Char> = emptyList(),
    val rackWildcards: Int = 0,
    val includeLetters: List<Char> = emptyList(),
    val excludeLetters: List<Char> = emptyList(),
    val includeVowelCount: Int? = null,
    val includeConsonantCount: Int? = null,
    val excludeVowelCount: Int? = null,
    val excludeConsonantCount: Int? = null,
    val includeLetterCounts: Map<Char, Int> = emptyMap(),
    val excludeLetterCounts: Map<Char, Int> = emptyMap(),
    val fixedLength: Int? = null,
    val isValid: Boolean = true,
    val errorMessage: String = ""
) {
    
    /**
     * Indica si requiere atril (rack) para la búsqueda
     */
    val requiresRack: Boolean
        get() = rackLetters.isNotEmpty() || rackWildcards > 0
    
    /**
     * Indica si tiene restricciones de filtro
     */
    val hasFilters: Boolean
        get() = includeLetters.isNotEmpty() || excludeLetters.isNotEmpty() ||
                includeVowelCount != null || includeConsonantCount != null ||
                excludeVowelCount != null || excludeConsonantCount != null ||
                includeLetterCounts.isNotEmpty() || excludeLetterCounts.isNotEmpty()
    
    /**
     * String completo del patrón original
     */
    fun toDebugString(): String = buildString {
        appendLine("ParsedPattern {")
        appendLine("  pattern: '$pattern'")
        appendLine("  rackLetters: $rackLetters")
        appendLine("  rackWildcards: $rackWildcards")
        appendLine("  includeLetters: $includeLetters")
        appendLine("  excludeLetters: $excludeLetters")
        appendLine("  includeVowelCount: $includeVowelCount")
        appendLine("  includeConsonantCount: $includeConsonantCount")
        appendLine("  excludeVowelCount: $excludeVowelCount")
        appendLine("  excludeConsonantCount: $excludeConsonantCount")
        appendLine("  includeLetterCounts: $includeLetterCounts")
        appendLine("  excludeLetterCounts: $excludeLetterCounts")
        appendLine("  fixedLength: $fixedLength")
        appendLine("  requiresRack: $requiresRack")
        appendLine("  hasFilters: $hasFilters")
        appendLine("  isValid: $isValid")
        if (errorMessage.isNotEmpty()) appendLine("  error: '$errorMessage'")
        appendLine("}")
    }
}

object PatternParser {
    
    /**
     * Normaliza dígrafos españoles para procesamiento interno
     */
    private fun normalizeSpanishDigraphs(input: String): String {
        return input.uppercase()
            .replace("CH", "Ç")
            .replace("LL", "K") 
            .replace("RR", "W")
    }
    
    /**
     * Desnormaliza dígrafos para visualización
     */
    private fun denormalizeSpanishDigraphs(input: String): String {
        return input
            .replace("Ç", "CH")
            .replace("K", "LL")
            .replace("W", "RR")
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
     * Parser principal que maneja la sintaxis completa
     * 
     * Sintaxis soportada:
     * 1. Patrón básico: "C.SA", "*+AEIOU", "C*.A"
     * 2. Con rack: "C.?,AER?", "*,AEIOU??"
     * 3. Con longitud: "C.SA:4", "*:6"
     * 4. Completo: "*.+AEIOU-BCDFG:6,AER??"
     * 5. Vocales/consonantes: "*@.@", "C&S&", "+3@:5", "+2&:4"
     * 6. Multiplicidad: "+UU", "+AAAA", "+2@-1&:6", "+4@:5"
     * 7. Notación algebraica L/R vs dígrafos:
     *    - "+2L:4" = 2 letras L individuales (no LL)
     *    - "+LL:4" = 1 dígrafo LL (elle)
     *    - "+3R:6" = 3 letras R individuales (no RR)
     *    - "+RR:6" = 1 dígrafo RR (erre)
     */
    fun parse(input: String): ParsedPattern {
        if (input.isBlank()) {
            return ParsedPattern(isValid = false, errorMessage = "Entrada vacía")
        }
        
        try {
            val normalizedInput = normalizeSpanishDigraphs(input.trim())
            
            // Separar por ':' para extraer longitud fija
            val lengthSplit = normalizedInput.split(":")
            val fixedLength = if (lengthSplit.size > 1) {
                lengthSplit[1].toIntOrNull()?.takeIf { it > 0 }
            } else null
            
            println("PatternParser: lengthSplit = $lengthSplit, fixedLength = $fixedLength")
            
            val mainPart = lengthSplit[0]
            
            // Separar por ',' para extraer rack
            val rackSplit = mainPart.split(",", limit = 2)
            val patternPart = rackSplit[0]
            val rackPart = if (rackSplit.size > 1) rackSplit[1] else ""
            
            // Analizar patrón principal con filtros avanzados
            val parsedFilters = parseAdvancedPatternWithFilters(patternPart)
            
            // Analizar rack
            val (rackLetters, rackWildcards) = parseRack(rackPart)
            
            // Validaciones
            val validationError = validateParsedComponents(
                parsedFilters.pattern, rackLetters, rackWildcards, parsedFilters.includeLetters, 
                parsedFilters.excludeLetters, fixedLength, parsedFilters
            )
            
            if (validationError != null) {
                return ParsedPattern(isValid = false, errorMessage = validationError)
            }
            
            return ParsedPattern(
                pattern = parsedFilters.pattern,
                rackLetters = rackLetters,
                rackWildcards = rackWildcards,
                includeLetters = parsedFilters.includeLetters,
                excludeLetters = parsedFilters.excludeLetters,
                includeVowelCount = parsedFilters.includeVowelCount,
                includeConsonantCount = parsedFilters.includeConsonantCount,
                excludeVowelCount = parsedFilters.excludeVowelCount,
                excludeConsonantCount = parsedFilters.excludeConsonantCount,
                includeLetterCounts = parsedFilters.includeLetterCounts,
                excludeLetterCounts = parsedFilters.excludeLetterCounts,
                fixedLength = fixedLength,
                isValid = true
            )
            
        } catch (e: Exception) {
            return ParsedPattern(
                isValid = false, 
                errorMessage = "Error de sintaxis: ${e.message}"
            )
        }
    }
    
    /**
     * Clase para almacenar resultados de parsing avanzado
     */
    private data class AdvancedPatternFilters(
        val pattern: String = "",
        val includeLetters: List<Char> = emptyList(),
        val excludeLetters: List<Char> = emptyList(),
        val includeVowelCount: Int? = null,
        val includeConsonantCount: Int? = null,
        val excludeVowelCount: Int? = null,
        val excludeConsonantCount: Int? = null,
        val includeLetterCounts: Map<Char, Int> = emptyMap(),
        val excludeLetterCounts: Map<Char, Int> = emptyMap()
    )
    
    /**
     * Extrae patrón y filtros avanzados (+/-) incluyendo vocales/consonantes y multiplicidad
     */
    private fun parseAdvancedPatternWithFilters(patternPart: String): AdvancedPatternFilters {
        var workingPattern = patternPart
        val includeLetters = mutableListOf<Char>()
        val excludeLetters = mutableListOf<Char>()
        val includeLetterCounts = mutableMapOf<Char, Int>()
        val excludeLetterCounts = mutableMapOf<Char, Int>()
        var includeVowelCount: Int? = null
        var includeConsonantCount: Int? = null
        var excludeVowelCount: Int? = null
        var excludeConsonantCount: Int? = null
        
        // Regex para filtros de inclusión con multiplicidad: +3@, +2&, +UU, +AAAA
        val includeMultiplicityRegex = Regex("""\+(\d*)([A-ZÇKWÑäëïöü@&]+)""")
        includeMultiplicityRegex.findAll(workingPattern).forEach { match ->
            val countStr = match.groupValues[1]
            val letters = match.groupValues[2]
            val count = if (countStr.isNotEmpty()) countStr.toInt() else 1
            
            when {
                letters == "@" -> includeVowelCount = count
                letters == "&" -> includeConsonantCount = count
                letters.all { it == '@' } -> includeVowelCount = letters.length
                letters.all { it == '&' } -> includeConsonantCount = letters.length
                countStr.isNotEmpty() && letters.length == 1 -> {
                    // Notación algebraica específica: +2L, +3R, etc.
                    includeLetterCounts[letters.first()] = count
                }
                letters.all { it == letters.first() } -> {
                    // Multiplicidad de letra específica (UU, AAAA)
                    includeLetterCounts[letters.first()] = letters.length
                }
                else -> {
                    // Letras normales
                    letters.forEach { char ->
                        when (char) {
                            '@' -> includeVowelCount = (includeVowelCount ?: 0) + 1
                            '&' -> includeConsonantCount = (includeConsonantCount ?: 0) + 1
                            else -> includeLetters.add(char)
                        }
                    }
                }
            }
            workingPattern = workingPattern.replace(match.value, "")
        }
        
        // Regex para filtros de exclusión con multiplicidad: -2@, -1&
        val excludeMultiplicityRegex = Regex("""-(\d*)([A-ZÇKWÑäëïöü@&]+)""")
        excludeMultiplicityRegex.findAll(workingPattern).forEach { match ->
            val countStr = match.groupValues[1]
            val letters = match.groupValues[2]
            val count = if (countStr.isNotEmpty()) countStr.toInt() else 1
            
            when {
                letters == "@" -> excludeVowelCount = count
                letters == "&" -> excludeConsonantCount = count
                letters.all { it == '@' } -> excludeVowelCount = letters.length
                letters.all { it == '&' } -> excludeConsonantCount = letters.length
                countStr.isNotEmpty() && letters.length == 1 -> {
                    // Notación algebraica específica: -2L, -3R, etc.
                    excludeLetterCounts[letters.first()] = count
                }
                letters.all { it == letters.first() } -> {
                    // Multiplicidad de exclusión de letra específica
                    excludeLetterCounts[letters.first()] = letters.length
                }
                else -> {
                    // Letras normales de exclusión
                    letters.forEach { char ->
                        when (char) {
                            '@' -> excludeVowelCount = (excludeVowelCount ?: 0) + 1
                            '&' -> excludeConsonantCount = (excludeConsonantCount ?: 0) + 1
                            else -> excludeLetters.add(char)
                        }
                    }
                }
            }
            workingPattern = workingPattern.replace(match.value, "")
        }
        
        // Limpiar patrón de espacios extra
        val cleanPattern = workingPattern.trim()
        
        return AdvancedPatternFilters(
            pattern = cleanPattern,
            includeLetters = includeLetters.distinct(),
            excludeLetters = excludeLetters.distinct(),
            includeVowelCount = includeVowelCount,
            includeConsonantCount = includeConsonantCount,
            excludeVowelCount = excludeVowelCount,
            excludeConsonantCount = excludeConsonantCount,
            includeLetterCounts = includeLetterCounts.toMap(),
            excludeLetterCounts = excludeLetterCounts.toMap()
        )
    }
    
    /**
     * Extrae patrón y filtros (+/-) de la parte del patrón (versión legacy)
     */
    private fun parsePatternWithFilters(patternPart: String): Triple<String, List<Char>, List<Char>> {
        var workingPattern = patternPart
        val includeLetters = mutableListOf<Char>()
        val excludeLetters = mutableListOf<Char>()
        
        // Extraer restricciones de inclusión (+LETRAS)
        val includeRegex = Regex("""\+([A-ZÇKWÑäëïöü]+)""")
        includeRegex.findAll(workingPattern).forEach { match ->
            val letters = match.groupValues[1]
            includeLetters.addAll(letters.toCharArray().toList())
            workingPattern = workingPattern.replace(match.value, "")
        }
        
        // Extraer restricciones de exclusión (-LETRAS)
        val excludeRegex = Regex("""-([A-ZÇKWÑäëïöü]+)""")
        excludeRegex.findAll(workingPattern).forEach { match ->
            val letters = match.groupValues[1]
            excludeLetters.addAll(letters.toCharArray().toList())
            workingPattern = workingPattern.replace(match.value, "")
        }
        
        // Limpiar patrón de espacios extra
        val cleanPattern = workingPattern.trim()
        
        return Triple(cleanPattern, includeLetters.distinct(), excludeLetters.distinct())
    }
    
    /**
     * Analiza la parte del rack para extraer letras y wildcards
     */
    private fun parseRack(rackPart: String): Pair<List<Char>, Int> {
        if (rackPart.isEmpty()) return Pair(emptyList(), 0)
        
        val rackLetters = mutableListOf<Char>()
        var wildcardCount = 0
        
        for (char in rackPart) {
            when (char) {
                '?' -> wildcardCount++
                ' ', ',' -> { /* ignorar separadores */ }
                else -> {
                    if (char.isLetter() || char in "ÇKWÑäëïöü") {
                        rackLetters.add(char.uppercaseChar())
                    }
                }
            }
        }
        
        return Pair(rackLetters, wildcardCount.coerceAtMost(2)) // Máximo 2 wildcards, mantener duplicados
    }
    
    /**
     * Valida los componentes parseados
     */
    private fun validateParsedComponents(
        pattern: String,
        rackLetters: List<Char>,
        rackWildcards: Int,
        includeLetters: List<Char>,
        excludeLetters: List<Char>,
        fixedLength: Int?,
        filters: AdvancedPatternFilters? = null
    ): String? {
        
        // Validar caracteres del patrón (ahora incluye @ y &)
        if (pattern.isNotEmpty()) {
            val validPatternChars = Regex("""[A-ZÇKWÑäëïöü*.?@&]+""")
            if (!validPatternChars.matches(pattern)) {
                return "Patrón contiene caracteres inválidos: $pattern"
            }
        }
        
        // Validar que no haya conflictos entre inclusión y exclusión
        val conflictLetters = includeLetters.intersect(excludeLetters.toSet())
        if (conflictLetters.isNotEmpty()) {
            return "Letras en conflicto entre inclusión y exclusión: $conflictLetters"
        }
        
        // Validar longitud fija
        if (fixedLength != null && (fixedLength < 1 || fixedLength > 20)) {
            return "Longitud fija debe estar entre 1 y 20: $fixedLength"
        }
        
        // Validar límite de wildcards
        if (rackWildcards > 2) {
            return "Máximo 2 wildcards permitidos en el rack"
        }
        
        // Validar filtros avanzados si están presentes
        filters?.let { f ->
            // Validar conteos de vocales/consonantes
            if (f.includeVowelCount != null && (f.includeVowelCount < 0 || f.includeVowelCount > 10)) {
                return "Conteo de vocales debe estar entre 0 y 10: ${f.includeVowelCount}"
            }
            if (f.includeConsonantCount != null && (f.includeConsonantCount < 0 || f.includeConsonantCount > 15)) {
                return "Conteo de consonantes debe estar entre 0 y 15: ${f.includeConsonantCount}"
            }
            
            // Validar conteos de letras específicas
            f.includeLetterCounts.forEach { (letter, count) ->
                if (count < 1 || count > 5) {
                    return "Conteo de letra '$letter' debe estar entre 1 y 5: $count"
                }
            }
        }
        
        return null // Todo válido
    }
    
    /**
     * Versión simplificada para casos básicos
     */
    fun isPatternSyntax(input: String): Boolean {
        return input.any { it in ".@&+:-*,?" }
    }
    
    /**
     * Extrae solo el patrón principal sin filtros para UI
     */
    fun extractMainPattern(input: String): String {
        val parsed = parse(input)
        return if (parsed.isValid) parsed.pattern else input
    }
}