package com.maslexico.android

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.border
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.*
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sin

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val context = LocalContext.current
    val dataManager = remember { DataManager.getInstance(context) }
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    
    var searchText by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<WildcardSearchResult?>(null) }
    var subanagrams by remember { mutableStateOf<Map<Int, List<WildcardWord>>>(emptyMap()) }
    var isSearching by remember { mutableStateOf(false) }
    var isLoadingSubanagrams by remember { mutableStateOf(false) }
    var validationResult by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var patternResults by remember { mutableStateOf<Map<Int, List<String>>>(emptyMap()) }
    var isLoadingPattern by remember { mutableStateOf(false) }
    var showHooks by remember { mutableStateOf(true) }
    var showSubanagrams by remember { mutableStateOf(false) }
    var hasSearched by remember { mutableStateOf(false) }
    var isResultsExpanded by remember { mutableStateOf(false) }
    var isExtraLetterExpanded by remember { mutableStateOf(false) }
    var isSubanagramsExpanded by remember { mutableStateOf(mapOf<Int, Boolean>()) }
    var isPatternGroupsExpanded by remember { mutableStateOf(mapOf<Int, Boolean>()) }
    var showLongPatternWords by remember { mutableStateOf(false) }
    
    // Derived state to detect modes
    val isValidationMode by remember { derivedStateOf { searchText.contains(" ") } }
    val isPatternMode by remember { derivedStateOf { 
        searchText.any { it in ".@&+:-*," } 
    } }
    
    fun performValidation() {
        if (searchText.isBlank()) return
        
        isSearching = true
        hasSearched = true
        
        // Clear focus to prevent keyboard bounce back
        focusManager.clearFocus()
        keyboardController?.hide()
        
        scope.launch {
            try {
                val words = searchText.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
                var isPlayValid = true
                
                // Check all words - if ANY word is invalid, the entire play is invalid
                for (word in words) {
                    val isWordValid = dataManager.validateWord(word)
                    if (!isWordValid) {
                        isPlayValid = false
                        break // No need to check further
                    }
                }
                
                validationResult = searchText.trim() to isPlayValid
                searchResults = null // Clear search results when in validation mode
                
            } catch (e: Exception) {
                validationResult = null
            } finally {
                isSearching = false
            }
        }
    }
    
    fun performPatternSearch() {
        if (searchText.isBlank()) return
        
        isLoadingPattern = true
        hasSearched = true
        
        // Clear focus to prevent keyboard bounce back
        focusManager.clearFocus()
        keyboardController?.hide()
        
        scope.launch {
            try {
                // Parse pattern syntax
                val parsedPattern = PatternParser.parse(searchText)
                
                if (!parsedPattern.isValid) {
                    println("❌ Pattern parse error: ${parsedPattern.errorMessage}")
                    patternResults = emptyMap()
                    return@launch
                }
                
                println("✅ Pattern parsed successfully:")
                println(parsedPattern.toDebugString())
                
                // Perform real pattern search using DataManager
                val patternSearchResults = dataManager.findPatternWords(parsedPattern)
                
                println("✅ Pattern search completed, found ${patternSearchResults.values.sumOf { it.size }} total words")
                
                patternResults = patternSearchResults
                searchResults = null // Clear search results when in pattern mode
                validationResult = null // Clear validation results when in pattern mode
                
            } catch (e: Exception) {
                println("❌ Pattern search error: ${e.message}")
                e.printStackTrace()
                patternResults = emptyMap()
            } finally {
                isLoadingPattern = false
            }
        }
    }
    
    fun performSearch() {
        if (searchText.isBlank()) return
        
        // Automatically detect mode and call appropriate function
        if (isValidationMode) {
            performValidation()
            return
        }
        
        if (isPatternMode) {
            performPatternSearch()
            return
        }
        
        isSearching = true
        hasSearched = true
        
        // Clear focus to prevent keyboard bounce back
        focusManager.clearFocus()
        keyboardController?.hide()
        
        scope.launch {
            try {
                val result = dataManager.findAnagramsWithWildcards(searchText.trim())
                searchResults = result
                validationResult = null // Clear validation results when in search mode
                isResultsExpanded = false // Start collapsed
                isExtraLetterExpanded = false // Start collapsed
            } catch (e: Exception) {
                // Handle error
                searchResults = WildcardSearchResult(emptyList(), emptyList(), emptyMap(), 0.0, "Error", searchText)
                isResultsExpanded = false
                isExtraLetterExpanded = false
            } finally {
                isSearching = false
            }
        }
    }
    
    fun clearSearch() {
        searchText = ""
        searchResults = null
        validationResult = null
        patternResults = emptyMap()
        subanagrams = emptyMap()
        hasSearched = false
        isResultsExpanded = false
        isExtraLetterExpanded = false
        isSubanagramsExpanded = mapOf()
        isPatternGroupsExpanded = mapOf()
        showLongPatternWords = false
    }
    
    // Generate subanagrams when toggle is enabled and we have search results
    LaunchedEffect(showSubanagrams, searchResults) {
        if (showSubanagrams && searchResults != null && searchResults!!.wildcardCount == 0) {
            val baseLetters = searchResults!!.query.replace("?", "")
            if (baseLetters.length >= 2) {
                isLoadingSubanagrams = true
                try {
                    subanagrams = dataManager.generateSubanagrams(baseLetters)
                } catch (e: Exception) {
                    subanagrams = emptyMap()
                } finally {
                    isLoadingSubanagrams = false
                }
            }
        } else {
            subanagrams = emptyMap()
        }
    }
    
    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet(
                modifier = Modifier.width(280.dp)
            ) {
                DrawerContent(
                    showHooks = showHooks,
                    onShowHooksChange = { showHooks = it },
                    onCloseDrawer = { 
                        scope.launch { drawerState.close() }
                    }
                )
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Spacer to push title down
            Spacer(modifier = Modifier.height(24.dp))
            
            // Title with hamburger menu
            Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Hamburger menu button
                    IconButton(
                        onClick = { 
                            scope.launch { drawerState.open() }
                        }
                    ) {
                        Icon(
                            Icons.Default.Menu,
                            contentDescription = "Menú",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                    
                    // Title
                    Text(
                        text = "+Léxico",
                        style = MaterialTheme.typography.headlineLarge.copy(
                            fontWeight = FontWeight.Bold,
                            fontSize = 28.sp
                        ),
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center
                    )
                    
                    // Spacer to balance the hamburger button
                    Spacer(modifier = Modifier.width(48.dp))
                }
            
            // Search Input with dynamic button
            OutlinedTextField(
            value = searchText,
            onValueChange = { 
                searchText = it.uppercase()
                // Reset search state when text changes
                if (hasSearched) {
                    hasSearched = false
                    searchResults = null
                }
            },
            placeholder = { Text("Ingresa letras...", fontSize = 24.sp) },
            textStyle = MaterialTheme.typography.titleLarge.copy(fontSize = 24.sp),
            trailingIcon = {
                // Dynamic button: Search/Clear based on state
                if (searchText.isNotEmpty()) {
                    if (isSearching || isLoadingPattern) {
                        // Show loading during search or pattern search
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.primary
                        )
                    } else if (hasSearched && (searchResults != null || patternResults.isNotEmpty() || validationResult != null)) {
                        // Show clear button when there are any search results (search, pattern, or validation)
                        IconButton(onClick = { clearSearch() }) {
                            Icon(Icons.Default.Clear, contentDescription = "Limpiar")
                        }
                    } else {
                        // Show search button when text entered but no search yet
                        IconButton(onClick = { performSearch() }) {
                            Icon(Icons.Default.Search, contentDescription = "Buscar")
                        }
                    }
                }
            },
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                imeAction = if (searchText.isNotEmpty() && !isSearching && !isLoadingPattern) ImeAction.Search else ImeAction.None
            ),
            keyboardActions = KeyboardActions(
                onSearch = { 
                    if (searchText.isNotEmpty() && !isSearching && !isLoadingPattern) {
                        performSearch() 
                    }
                }
            ),
                    modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            
            // Toggle for >8 letters in pattern mode
            if (isPatternMode && patternResults.isNotEmpty()) {
                Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Resultados > 8 letras:",
                    color = MaterialTheme.colorScheme.onBackground
                )
                Spacer(modifier = Modifier.width(8.dp))
                Switch(
                    checked = showLongPatternWords,
                    onCheckedChange = { 
                        showLongPatternWords = it
                        // Reset expansion states when switching
                        isPatternGroupsExpanded = mapOf()
                    }
                )
                    }
                }
            }
            
            // Palabras más cortas Toggle (centered) - Only show in anagram search mode
            if (!isValidationMode && !isPatternMode) {
                item {
                    Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Mostrar subanagramas:",
                    color = if (searchResults?.wildcardCount == 0) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.width(8.dp))
                Switch(
                    checked = showSubanagrams && (searchResults?.wildcardCount == 0),
                    onCheckedChange = { 
                        if (searchResults?.wildcardCount == 0) {
                            showSubanagrams = it 
                        }
                    },
                    enabled = searchResults?.wildcardCount == 0
                )
                    }
                }
            }
            
            // Validation Results
            validationResult?.let { (play, isValid) ->
                item {
                    ValidationResultView(
                        play = play,
                        isValid = isValid,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            
            // Pattern Results with enhanced UI
            if (patternResults.isNotEmpty()) {
                item {
                    EnhancedPatternResultsView(
                patternResults = patternResults,
                showHooks = showHooks,
                dataManager = dataManager,
                showLongWords = showLongPatternWords,
                isGroupsExpanded = isPatternGroupsExpanded,
                onGroupExpandChange = { length, expanded ->
                    isPatternGroupsExpanded = isPatternGroupsExpanded.toMutableMap().apply {
                        put(length, expanded)
                    }
                },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
            
            // Loading indicator for pattern search
            if (isLoadingPattern) {
                item {
                    Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Buscando patrones...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
                    }
                }
            }
            
            // Search Results (only show when in anagram mode)
            if (!isValidationMode && !isPatternMode) {
                searchResults?.let { result ->
                    if (result.wildcardCount > 2) {
                        item {
                            Text(
                                text = "Máximo 2 comodines (?)",
                                style = MaterialTheme.typography.bodyLarge,
                                textAlign = TextAlign.Center,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(32.dp)
                            )
                        }
                    } else if (showSubanagrams && result.wildcardCount == 0) {
                        // Show ONLY subanagrams when toggle is on
                        if (isLoadingSubanagrams) {
                            item {
                                Card(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(32.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            CircularProgressIndicator(
                                                modifier = Modifier.size(20.dp),
                                                strokeWidth = 2.dp,
                                                color = MaterialTheme.colorScheme.tertiary
                                            )
                                            Spacer(modifier = Modifier.width(12.dp))
                                            Text(
                                                text = "Generando palabras más cortas...",
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.tertiary
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            // Subanagrams summary header
                            val totalSubanagrams = subanagrams.values.sumOf { it.size }
                            
                            item {
                                Card(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp),
                                    colors = CardDefaults.cardColors(
                                        containerColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.1f)
                                    )
                                ) {
                                    Column(
                                        modifier = Modifier.padding(16.dp)
                                    ) {
                                        Text(
                                            text = "$totalSubanagrams palabras más cortas",
                                            style = MaterialTheme.typography.titleLarge.copy(
                                                fontWeight = FontWeight.Bold
                                            ),
                                            color = MaterialTheme.colorScheme.tertiary
                                        )
                                    }
                                }
                            }
                            
                            // Display subanagrams grouped by length (descending order)
                            subanagrams.toSortedMap(reverseOrder()).forEach { (length, words) ->
                                val isExpanded = isSubanagramsExpanded[length] ?: false
                                
                                item {
                                    Card(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 4.dp)
                                    ) {
                                        Column {
                                            // Header with expand/collapse functionality
                                            Row(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .clickable { 
                                                        isSubanagramsExpanded = isSubanagramsExpanded.toMutableMap().apply {
                                                            put(length, !isExpanded)
                                                        }
                                                    }
                                                    .padding(16.dp),
                                                horizontalArrangement = Arrangement.SpaceBetween,
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Text(
                                                    text = "${words.size} palabras de $length letras",
                                                    style = MaterialTheme.typography.titleMedium.copy(
                                                        fontWeight = FontWeight.Bold
                                                    ),
                                                    color = MaterialTheme.colorScheme.tertiary
                                                )
                                                
                                                Icon(
                                                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                                    contentDescription = if (isExpanded) "Colapsar" else "Expandir",
                                                    tint = MaterialTheme.colorScheme.tertiary
                                                )
                                            }
                                        }
                                    }
                                }
                                
                                // Expandable content - each word as separate LazyColumn item
                                if (isExpanded) {
                                    items(words) { wildcardWord ->
                                        WildcardWordItem(
                                            wildcardWord = wildcardWord,
                                            showHooks = showHooks,
                                            dataManager = dataManager,
                                            baseLetters = ""
                                        )
                                    }
                                }
                            }
                        }
            } else {
                            // Show NORMAL results (anagrams + extra letter) when subanagrams toggle is OFF
                            // Collapsible results section header
                            item {
                                Card(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 8.dp)
                                ) {
                                    // Header with expand/collapse functionality
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { isResultsExpanded = !isResultsExpanded }
                                            .padding(16.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            val exactCount = result.exactWords.size
                                            val exactText = if (exactCount == 0) {
                                                buildAnnotatedString {
                                                    withStyle(SpanStyle(color = Color.Red)) {
                                                        append("0")
                                                    }
                                                    withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) {
                                                        append(" resultados con todas las fichas")
                                                    }
                                                }
                                            } else {
                                                buildAnnotatedString {
                                                    withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) {
                                                        append("$exactCount resultados con todas las fichas")
                                                    }
                                                }
                                            }
                                            
                                            Text(
                                                text = exactText,
                                                style = MaterialTheme.typography.titleMedium.copy(
                                                    fontWeight = FontWeight.Bold
                                                )
                                            )
                                            
                                            if (result.wildcardCount > 0 && result.possibleWildcardLetters.isNotEmpty()) {
                                                Text(
                                                    text = "Comodines pueden ser: ${formatLetterHints(result.possibleWildcardLetters)}",
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                    modifier = Modifier.padding(top = 2.dp)
                                                )
                                            }
                                        }
                                        
                                        Icon(
                                            imageVector = if (isResultsExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                            contentDescription = if (isResultsExpanded) "Colapsar" else "Expandir",
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                    }
                                }
                            }
                            
                            // Expandable content - each exact word as separate LazyColumn item
                            if (isResultsExpanded && result.exactWords.isNotEmpty()) {
                                items(result.exactWords) { wildcardWord ->
                                    WildcardWordItem(
                                        wildcardWord = wildcardWord,
                                        showHooks = showHooks,
                                        dataManager = dataManager,
                                        baseLetters = result.query.replace("?", "")
                                    )
                                }
                            }
                            
                            // Extra Letter Results Section (always show if searched)
                            if (hasSearched) {
                                item {
                                    Card(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 8.dp)
                                    ) {
                                        // Header with expand/collapse functionality
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clickable { isExtraLetterExpanded = !isExtraLetterExpanded }
                                                .padding(16.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Column(modifier = Modifier.weight(1f)) {
                                                val extraCount = result.extraLetterWords.size
                                                val extraText = if (extraCount == 0) {
                                                    buildAnnotatedString {
                                                        withStyle(SpanStyle(color = Color.Red)) {
                                                            append("0")
                                                        }
                                                        withStyle(SpanStyle(color = MaterialTheme.colorScheme.secondary)) {
                                                            append(" resultados con letra adicional")
                                                        }
                                                    }
                                                } else {
                                                    buildAnnotatedString {
                                                        withStyle(SpanStyle(color = MaterialTheme.colorScheme.secondary)) {
                                                            append("$extraCount resultados con letra adicional")
                                                        }
                                                    }
                                                }
                                                
                                                Text(
                                                    text = extraText,
                                                    style = MaterialTheme.typography.titleMedium.copy(
                                                        fontWeight = FontWeight.Bold
                                                    )
                                                )
                                                
                                                if (result.possibleExtraLetters.isNotEmpty()) {
                                                    Text(
                                                        text = "Letras adicionales: ${formatLetterHints(result.possibleExtraLetters)}",
                                                        style = MaterialTheme.typography.bodySmall,
                                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                        modifier = Modifier.padding(top = 2.dp)
                                                    )
                                                }
                                            }
                                            
                                            Icon(
                                                imageVector = if (isExtraLetterExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                                contentDescription = if (isExtraLetterExpanded) "Colapsar" else "Expandir",
                                                tint = MaterialTheme.colorScheme.secondary
                                            )
                                        }
                                    }
                                }
                                
                                // Expandable content - each extra letter word as separate LazyColumn item
                                if (isExtraLetterExpanded && result.extraLetterWords.isNotEmpty()) {
                                    items(result.extraLetterWords) { wildcardWord ->
                                        WildcardWordItem(
                                            wildcardWord = wildcardWord,
                                            showHooks = showHooks,
                                            dataManager = dataManager,
                                            baseLetters = result.query.replace("?", "")
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Empty space when no search - handled by LazyColumn automatically
        }
    }
}

@Composable
fun WildcardWordItem(
    wildcardWord: WildcardWord,
    showHooks: Boolean,
    dataManager: DataManager,
    baseLetters: String = ""
) {
    var hooks by remember { mutableStateOf<WordHooks?>(null) }
    val scope = rememberCoroutineScope()
    
    LaunchedEffect(wildcardWord.word, showHooks) {
        if (showHooks) {
            scope.launch {
                hooks = dataManager.findHooks(wildcardWord.word)
            }
        }
    }
    
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp) // Reducido de 4dp a 2dp
    ) {
        // Centered beautiful word display with hooks
        BeautifulWordDisplay(
            word = SpanishUtils.denormalizeWord(wildcardWord.word),
            highlightedLetters = wildcardWord.highlightedLetters,
            highlightedPositions = wildcardWord.getHighlightedPositions(baseLetters),
            baseLetters = baseLetters,
            hooks = if (showHooks) hooks else null,
            groupLength = baseLetters.length
        )
    }
}

@Composable
fun BeautifulWordDisplay(
    word: String,
    highlightedLetters: List<Char>,
    highlightedPositions: Set<Int> = emptySet(),
    baseLetters: String,
    hooks: WordHooks?,
    groupLength: Int = word.length // Nueva parámetro para longitud del grupo
) {
    // Calcular ancho central basado en longitud del grupo (n+2)
    val adjustedLength = groupLength + 2
    val minWordWidth = when {
        adjustedLength <= 5 -> 60.dp   // Grupos muy cortos (3+2)
        adjustedLength <= 7 -> 80.dp   // Grupos cortos (5+2)
        adjustedLength <= 9 -> 120.dp  // Grupos medianos (7+2)
        adjustedLength <= 11 -> 160.dp // Grupos largos (9+2)
        else -> 200.dp                 // Grupos muy largos
    }
    // Layout súper simple: palabra centrada, ganchos usan espacio libre
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp), // Reducido de 8dp a 4dp
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Ganchos izquierdos: usan espacio libre, wrap automático
        if (hooks?.leftExternal?.isNotEmpty() == true) {
            FlexibleHooksText(
                hooks = sortHooksSpanishOrder(hooks.leftExternal),
                alignment = Alignment.End,
                modifier = Modifier.weight(1f)
            )
        } else {
            // Espacio vacío pero equilibrado
            Spacer(modifier = Modifier.weight(1f))
        }
        
        Spacer(modifier = Modifier.width(8.dp))
        
        // Palabra principal: ancho fijo garantizado según longitud
        Box(
            modifier = Modifier.width(minWordWidth),
            contentAlignment = Alignment.Center
        ) {
            WordWithInternalHooksAttenuated(
                word = word,
                highlightedLetters = highlightedLetters,
                highlightedPositions = highlightedPositions,
                baseLetters = baseLetters,
                leftInternalHooks = hooks?.leftInternal ?: "",
                rightInternalHooks = hooks?.rightInternal ?: ""
            )
        }
        
        Spacer(modifier = Modifier.width(8.dp))
        
        // Ganchos derechos: usan espacio libre, wrap automático
        if (hooks?.rightExternal?.isNotEmpty() == true) {
            FlexibleHooksText(
                hooks = sortHooksSpanishOrder(hooks.rightExternal),
                alignment = Alignment.Start,
                modifier = Modifier.weight(1f)
            )
        } else {
            // Espacio vacío pero equilibrado
            Spacer(modifier = Modifier.weight(1f))
        }
    }
}

@Composable
fun FlexibleHooksText(
    hooks: String,
    alignment: Alignment.Horizontal,
    modifier: Modifier = Modifier
) {
    // Texto flexible que usa todo el espacio disponible con wrap automático
    val displayHooks = SpanishUtils.denormalizeWord(hooks).lowercase()
    
    // Crear texto con espaciado uniforme entre elementos
    val styledText = buildAnnotatedString {
        var i = 0
        while (i < displayHooks.length) {
            val digraphCheck = if (i < displayHooks.length - 1) displayHooks.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.lowercase() in listOf("ch", "ll", "rr")
            
            // Agregar espacio antes de cualquier elemento (excepto el primero)
            if (i > 0) {
                append(" ")
            }
            
            if (isDigraph) {
                // Dígrafos sin cursiva
                append(digraphCheck)
                i += 2
            } else {
                // Letras individuales
                append(displayHooks[i])
                i += 1
            }
        }
    }
    
    Text(
        text = styledText,
        style = MaterialTheme.typography.titleMedium.copy(
            fontWeight = FontWeight.SemiBold,
            fontSize = 18.sp
        ),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = when (alignment) {
            Alignment.Start -> TextAlign.Start
            Alignment.End -> TextAlign.End
            else -> TextAlign.Center
        },
        overflow = TextOverflow.Visible,
        modifier = modifier.padding(2.dp)
    )
}

/**
 * Ordena los ganchos según el orden alfabético español con dígrafos
 * A B C CH D E F G H I J K L LL M N Ñ O P Q R RR S T U V W X Y Z
 */
fun sortHooksSpanishOrder(hooks: String): String {
    // Primero desnormalizar para obtener los dígrafos reales
    val denormalizedHooks = SpanishUtils.denormalizeWord(hooks).uppercase()
    
    // Orden alfabético español con dígrafos
    val spanishOrder = listOf(
        "A", "B", "C", "CH", "D", "E", "F", "G", "H", "I", "J", "K", "L", "LL", 
        "M", "N", "Ñ", "O", "P", "Q", "R", "RR", "S", "T", "U", "V", "W", "X", "Y", "Z"
    )
    
    // Extraer todos los caracteres y dígrafos
    val characters = mutableListOf<String>()
    var i = 0
    while (i < denormalizedHooks.length) {
        val digraphCheck = if (i < denormalizedHooks.length - 1) {
            denormalizedHooks.substring(i, i + 2)
        } else ""
        
        val isDigraph = digraphCheck in listOf("CH", "LL", "RR")
        
        if (isDigraph) {
            characters.add(digraphCheck)
            i += 2
        } else {
            characters.add(denormalizedHooks[i].toString())
            i += 1
        }
    }
    
    // Ordenar según el orden español
    val sortedCharacters = characters.sortedBy { char ->
        val index = spanishOrder.indexOf(char)
        if (index == -1) spanishOrder.size else index
    }
    
    // Reconvertir a string normalizado para almacenamiento
    return SpanishUtils.normalizeWord(sortedCharacters.joinToString(""))
}

@Composable
fun MultiLineHooksText(
    hooks: String,
    isInternal: Boolean,
    alignment: Alignment.Horizontal
) {
    // Denormalize hooks to show natural digraphs
    val displayHooks = SpanishUtils.denormalizeWord(hooks).lowercase()
    
    // Create styled text with proper spacing between all elements
    val styledText = buildAnnotatedString {
        var i = 0
        while (i < displayHooks.length) {
            val digraphCheck = if (i < displayHooks.length - 1) displayHooks.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.lowercase() in listOf("ch", "ll", "rr")
            
            // Agregar espacio antes de cualquier elemento (excepto el primero)
            if (i > 0) {
                append(" ")
            }
            
            if (isDigraph) {
                // Dígrafos sin cursiva (el espaciado los hace claros)
                append(digraphCheck)
                i += 2
            } else {
                // Letras individuales
                append(displayHooks[i])
                i += 1
            }
        }
    }
    
    Text(
        text = styledText,
        style = MaterialTheme.typography.titleMedium.copy( // Cambiado de bodyMedium a titleMedium (más grande)
            fontWeight = if (isInternal) FontWeight.Normal else FontWeight.SemiBold, // Más peso
            fontSize = 18.sp // Tamaño específico más grande
        ),
        color = if (isInternal) {
            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f) // Attenuated for internal
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        textAlign = when (alignment) {
            Alignment.Start -> TextAlign.Start
            Alignment.End -> TextAlign.End
            else -> TextAlign.Center
        },
        lineHeight = 20.sp, // Aumentado para mejor legibilidad
        modifier = Modifier.fillMaxWidth()
    )
}

@Composable
fun WordWithInternalHooksAttenuated(
    word: String,
    highlightedLetters: List<Char>,
    highlightedPositions: Set<Int> = emptySet(),
    baseLetters: String,
    leftInternalHooks: String,
    rightInternalHooks: String,
    modifier: Modifier = Modifier
) {
    // Denormalize internal hooks to get the actual characters that should be attenuated
    val leftInternalChars = SpanishUtils.denormalizeWord(leftInternalHooks).uppercase()
    val rightInternalChars = SpanishUtils.denormalizeWord(rightInternalHooks).uppercase()
    
    // Create annotated string with internal hooks attenuated and position-based highlighting
    val annotatedString = buildAnnotatedString {
        // Convert word to normalized positions for mapping
        val normalizedWord = SpanishUtils.normalizeWord(word)
        var normalizedPos = 0
        var i = 0
        
        while (i < word.length) {
            // Check for digraphs first
            val digraphCheck = if (i < word.length - 1) word.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.uppercase() in listOf("CH", "LL", "RR")
            
            if (isDigraph) {
                // For digraphs, check if the normalized position should be highlighted
                val isHighlighted = normalizedPos in highlightedPositions
                
                // Check if this digraph is an internal hook
                val isInternalHook = digraphCheck.uppercase() in leftInternalChars || 
                                   digraphCheck.uppercase() in rightInternalChars
                
                val baseColor = if (isHighlighted) Color.Red else MaterialTheme.colorScheme.primary
                val finalColor = if (isInternalHook) baseColor.copy(alpha = 0.5f) else baseColor
                
                withStyle(SpanStyle(color = finalColor)) {
                    append(digraphCheck)
                }
                i += 2
                normalizedPos += 1 // Digraph counts as 1 position in normalized form
            } else {
                val char = word[i]
                // Check if this normalized position should be highlighted
                val isHighlighted = normalizedPos in highlightedPositions
                
                // Check if this character is an internal hook
                val isInternalHook = char.toString().uppercase() in leftInternalChars || 
                                   char.toString().uppercase() in rightInternalChars
                
                val baseColor = if (isHighlighted) Color.Red else MaterialTheme.colorScheme.primary
                val finalColor = if (isInternalHook) baseColor.copy(alpha = 0.5f) else baseColor
                
                withStyle(SpanStyle(color = finalColor)) {
                    append(char)
                }
                i += 1
                normalizedPos += 1
            }
        }
    }
    
    Text(
        text = annotatedString,
        style = MaterialTheme.typography.titleLarge.copy(
            fontWeight = FontWeight.Bold,
            fontSize = 20.sp
        ),
        textAlign = TextAlign.Center,
        modifier = modifier
    )
}

@Composable
fun CenteredWordText(
    word: String,
    highlightedLetters: List<Char>,
    baseLetters: String
) {
    // Simple highlighted word without breathing effects
    val annotatedString = buildAnnotatedString {
        val highlightedLettersNormalized = highlightedLetters.toSet()
        var i = 0
        
        while (i < word.length) {
            // Check for digraphs first
            val digraphCheck = if (i < word.length - 1) word.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.uppercase() in listOf("CH", "LL", "RR")
            
            if (isDigraph) {
                val normalizedDigraph = SpanishUtils.normalizeWord(digraphCheck).firstOrNull() ?: digraphCheck.first()
                val isHighlighted = normalizedDigraph in highlightedLettersNormalized
                val color = if (isHighlighted) Color.Red else MaterialTheme.colorScheme.primary
                
                withStyle(SpanStyle(color = color)) {
                    append(digraphCheck)
                }
                i += 2
            } else {
                val char = word[i]
                val normalizedChar = SpanishUtils.normalizeWord(char.toString()).firstOrNull() ?: char
                val isHighlighted = normalizedChar in highlightedLettersNormalized
                val color = if (isHighlighted) Color.Red else MaterialTheme.colorScheme.primary
                
                withStyle(SpanStyle(color = color)) {
                    append(char)
                }
                i += 1
            }
        }
    }
    
    Text(
        text = annotatedString,
        style = MaterialTheme.typography.titleLarge.copy(
            fontWeight = FontWeight.Bold,
            fontSize = 20.sp
        ),
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth()
    )
}

@Composable
fun BeautifulWordWithInternalHooks(
    word: String,
    highlightedLetters: List<Char>,
    baseLetters: String,
    leftInternalHooks: String,
    rightInternalHooks: String,
    style: androidx.compose.ui.text.TextStyle,
    normalColor: Color,
    highlightColor: Color
) {
    // Beautiful breathing effect for internal hooks
    val infiniteTransition = rememberInfiniteTransition(label = "breathing")
    val internalHooksAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = 2000,
                easing = FastOutSlowInEasing
            ),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha_breathing"
    )
    
    // Denormalize internal hooks to get the actual characters that should fade
    val leftInternalChars = SpanishUtils.denormalizeWord(leftInternalHooks)
    val rightInternalChars = SpanishUtils.denormalizeWord(rightInternalHooks)
    
    // Create advanced annotated string with selective effects
    val annotatedString = buildAnnotatedString {
        val highlightedLettersNormalized = highlightedLetters.toSet()
        var i = 0
        
        while (i < word.length) {
            // Check for digraphs first
            val digraphCheck = if (i < word.length - 1) word.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.uppercase() in listOf("CH", "LL", "RR")
            
            if (isDigraph) {
                // Handle digraph as a unit
                val normalizedDigraph = SpanishUtils.normalizeWord(digraphCheck).firstOrNull() ?: digraphCheck.first()
                
                // Determine color and alpha
                val isHighlighted = normalizedDigraph in highlightedLettersNormalized
                val isLeftInternal = digraphCheck in leftInternalChars
                val isRightInternal = digraphCheck in rightInternalChars
                val isFadeTarget = isLeftInternal || isRightInternal
                
                val color = if (isHighlighted) highlightColor else normalColor
                val alpha = if (isFadeTarget) internalHooksAlpha else 1f
                
                withStyle(SpanStyle(color = color.copy(alpha = alpha))) {
                    append(digraphCheck)
                }
                i += 2
            } else {
                // Handle single character
                val char = word[i]
                val normalizedChar = SpanishUtils.normalizeWord(char.toString()).firstOrNull() ?: char
                
                // Determine color and alpha
                val isHighlighted = normalizedChar in highlightedLettersNormalized
                val isLeftInternal = char.toString() in leftInternalChars
                val isRightInternal = char.toString() in rightInternalChars
                val isFadeTarget = isLeftInternal || isRightInternal
                
                val color = if (isHighlighted) highlightColor else normalColor
                val alpha = if (isFadeTarget) internalHooksAlpha else 1f
                
                withStyle(SpanStyle(color = color.copy(alpha = alpha))) {
                    append(char)
                }
                i += 1
            }
        }
    }
    
    Text(
        text = annotatedString,
        style = style
    )
}


@Composable
fun ExternalHooksText(
    hooks: String,
    modifier: Modifier = Modifier
) {
    // Denormalize hooks to show natural digraphs
    val displayHooks = SpanishUtils.denormalizeWord(hooks).lowercase()
    
    // Create styled text with italic only for digraphs
    val styledText = buildAnnotatedString {
        var i = 0
        while (i < displayHooks.length) {
            val digraphCheck = if (i < displayHooks.length - 1) displayHooks.substring(i, i + 2) else ""
            val isDigraph = digraphCheck.lowercase() in listOf("ch", "ll", "rr")
            
            if (isDigraph) {
                // Digraph in italic
                withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                    append(digraphCheck)
                }
                i += 2
            } else {
                // Regular letter
                append(displayHooks[i])
                i += 1
            }
        }
    }
    
    Text(
        text = styledText,
        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Normal),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
    )
}


@Composable
fun HighlightedWordText(
    word: String,
    wildcardLetters: List<Char>,
    baseLetters: String,
    style: androidx.compose.ui.text.TextStyle,
    normalColor: Color,
    highlightColor: Color
) {
    if (wildcardLetters.isEmpty()) {
        // No wildcards, show normal text
        Text(
            text = word,
            style = style,
            color = normalColor
        )
    } else {
        // Handle digraphs correctly when highlighting
        val annotatedString = buildAnnotatedString {
            val highlightedLetters = mutableSetOf<Char>()
            var i = 0
            
            while (i < word.length) {
                // Check for digraphs first
                val digraphCheck = if (i < word.length - 1) word.substring(i, i + 2) else ""
                val isDigraph = digraphCheck in listOf("CH", "LL", "RR")
                
                if (isDigraph) {
                    // Handle digraph
                    val normalizedDigraph = SpanishUtils.normalizeWord(digraphCheck).firstOrNull() ?: digraphCheck.first()
                    
                    if (normalizedDigraph in wildcardLetters && normalizedDigraph !in highlightedLetters) {
                        // Highlight the whole digraph
                        withStyle(SpanStyle(color = highlightColor)) {
                            append(digraphCheck)
                        }
                        highlightedLetters.add(normalizedDigraph)
                    } else {
                        // Normal digraph
                        withStyle(SpanStyle(color = normalColor)) {
                            append(digraphCheck)
                        }
                    }
                    i += 2 // Skip next character since we processed a digraph
                } else {
                    // Handle single character
                    val char = word[i]
                    val normalizedChar = SpanishUtils.normalizeWord(char.toString()).firstOrNull() ?: char
                    
                    if (normalizedChar in wildcardLetters && normalizedChar !in highlightedLetters) {
                        // Highlight first occurrence of this wildcard letter
                        withStyle(SpanStyle(color = highlightColor)) {
                            append(char)
                        }
                        highlightedLetters.add(normalizedChar)
                    } else {
                        // Normal letter
                        withStyle(SpanStyle(color = normalColor)) {
                            append(char)
                        }
                    }
                    i += 1
                }
            }
        }
        
        Text(
            text = annotatedString,
            style = style
        )
    }
}

@Composable
fun WordItem(
    word: String,
    showHooks: Boolean,
    dataManager: DataManager
) {
    WildcardWordItem(
        wildcardWord = WildcardWord(word),
        showHooks = showHooks,
        dataManager = dataManager
    )
}

@Composable
fun DrawerContent(
    showHooks: Boolean,
    onShowHooksChange: (Boolean) -> Unit,
    onCloseDrawer: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp)
    ) {
        // Header
        Text(
            text = "Configuración",
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.Bold
            ),
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(bottom = 16.dp)
        )
        
        // Hooks Toggle
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Mostrar ganchos",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            
            Switch(
                checked = showHooks,
                onCheckedChange = onShowHooksChange
            )
        }
        
        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
fun ValidationResultView(
    play: String,
    isValid: Boolean,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .padding(16.dp)
            .fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isValid) Color(0xFF4CAF50) else Color(0xFFF44336) // Green or Red
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            contentAlignment = Alignment.CenterStart
        ) {
            // Split words and join with line breaks
            val words = play.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            val formattedText = words.joinToString(separator = "\n") { word ->
                SpanishUtils.denormalizeWord(word).uppercase()
            }
            
            Text(
                text = formattedText,
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontWeight = FontWeight.Bold,
                    fontSize = 32.sp
                ),
                color = Color.White,
                textAlign = TextAlign.Start,
                lineHeight = 40.sp
            )
        }
    }
}

@Composable
fun EnhancedPatternResultsView(
    patternResults: Map<Int, List<String>>,
    showHooks: Boolean,
    dataManager: DataManager,
    showLongWords: Boolean,
    isGroupsExpanded: Map<Int, Boolean>,
    onGroupExpandChange: (Int, Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    // Filter and sort results based on toggle
    val filteredAndSortedResults = if (showLongWords) {
        // Show only 9+ letters, sorted ascending (9, 10, 11, ...)
        patternResults.filter { it.key >= 9 }.toSortedMap()
    } else {
        // Show 2-8 letters, sorted descending (8, 7, 6, ..., 2)
        patternResults.filter { it.key <= 8 }.toSortedMap(reverseOrder())
    }
    
    if (filteredAndSortedResults.isEmpty()) {
        // Show message when no results in current filter
        Card(
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
            )
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (showLongWords) {
                        "No hay resultados de 9+ letras"
                    } else {
                        "No hay resultados de 2-8 letras"
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        }
        return
    }
    
    Column(modifier = modifier) {
        // Header with total count for current filter
        val totalResults = filteredAndSortedResults.values.sumOf { it.size }
        val lengthRange = if (showLongWords) "9+ letras" else "2-8 letras"
        
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
            )
        ) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "$totalResults resultados de patrón ($lengthRange)",
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.Bold
                    ),
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
        
        // Scrollable results grouped by length with collapsible functionality
        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(filteredAndSortedResults.toList()) { (length, words) ->
                val isExpanded = isGroupsExpanded[length] ?: false
                
                Card(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column {
                        // Collapsible header
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { 
                                    onGroupExpandChange(length, !isExpanded)
                                }
                                .padding(16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "${words.size} palabras de $length letras",
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Bold
                                ),
                                color = MaterialTheme.colorScheme.primary
                            )
                            
                            Icon(
                                imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                contentDescription = if (isExpanded) "Colapsar" else "Expandir",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                        
                        // Expandable content - usar Column simple sin scroll anidado
                        if (isExpanded) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 8.dp, vertical = 8.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                words.forEach { word ->
                                    WildcardWordItem(
                                        wildcardWord = WildcardWord(word),
                                        showHooks = showHooks,
                                        dataManager = dataManager,
                                        baseLetters = ""
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Denormaliza y ordena letras según el orden alfabético español tradicional con dígrafos
 * Convierte Ç→CH, K→LL, W→RR y ordena según: A B C CH D E F G H I J K L LL M N Ñ O P Q R RR S T U V W X Y Z
 */
fun formatLetterHints(letters: Set<Char>): String {
    // Denormalizar cada letra
    val denormalizedLetters = letters.map { letter ->
        when (letter.uppercaseChar()) {
            'Ç' -> "CH"
            'K' -> "LL"
            'W' -> "RR"
            else -> letter.toString().uppercase()
        }
    }
    
    // Orden alfabético español tradicional con dígrafos
    val spanishOrder = listOf(
        "A", "B", "C", "CH", "D", "E", "F", "G", "H", "I", "J", "K", "L", "LL", 
        "M", "N", "Ñ", "O", "P", "Q", "R", "RR", "S", "T", "U", "V", "W", "X", "Y", "Z"
    )
    
    // Ordenar según el orden español y convertir a minúsculas para display
    val sortedLetters = denormalizedLetters.sortedBy { letter ->
        spanishOrder.indexOf(letter).takeIf { it >= 0 } ?: Int.MAX_VALUE
    }.map { it.lowercase() }
    
    return sortedLetters.joinToString(", ")
}