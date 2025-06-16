#!/usr/bin/env python3

import sqlite3
import time
from datetime import datetime

def log(message):
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] {message}")

def generate_hooks():
    db_path = "/Users/isaacfalconer/Library/Mobile Documents/com~apple~CloudDocs/XcodeProjects/ScrabbleFinder/ScrabbleFinder/Resources/scrabble_words.sqlite"
    
    log("🔗 Generador de Hooks COMPLETO en Python")
    log("═" * 50)
    
    # Conectar a la base de datos
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL") 
    cursor = conn.cursor()
    
    # Crear tabla de hooks (borrar si existe)
    log("🔧 Creando tabla de hooks...")
    cursor.execute("DROP TABLE IF EXISTS word_hooks")
    cursor.execute("""
        CREATE TABLE word_hooks (
            word TEXT PRIMARY KEY,
            left_hooks TEXT DEFAULT '',
            right_hooks TEXT DEFAULT '',
            left_internal_hooks TEXT DEFAULT '',
            right_internal_hooks TEXT DEFAULT ''
        )
    """)
    conn.commit()
    
    # Cargar todas las palabras
    log("📚 Cargando diccionario...")
    cursor.execute("SELECT DISTINCT word FROM words ORDER BY word")
    all_words = [row[0] for row in cursor.fetchall()]
    word_set = set(all_words)
    log(f"✅ Cargadas {len(all_words)} palabras")
    
    # Alfabeto español con digrafos
    alphabet = "ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW"
    
    log("⚡ Generando hooks externos e internos...")
    start_time = time.time()
    
    processed = 0
    external_hooks_count = 0
    internal_hooks_count = 0
    
    # Procesar en lotes
    batch_size = 5000
    for i in range(0, len(all_words), batch_size):
        batch = all_words[i:i + batch_size]
        
        # Iniciar transacción
        cursor.execute("BEGIN")
        
        for word in batch:
            # HOOKS EXTERNOS (extensiones)
            left_external = ""
            right_external = ""
            
            for letter in alphabet:
                # Hook izquierdo: ¿podemos añadir esta letra a la izquierda?
                if (letter + word) in word_set:
                    left_external += letter
                    
                # Hook derecho: ¿podemos añadir esta letra a la derecha?
                if (word + letter) in word_set:
                    right_external += letter
            
            # HOOKS INTERNOS (reducciones) - solo para palabras > 2 letras
            left_internal = ""
            right_internal = ""
            
            if len(word) > 2:
                # Hook interno izquierdo: ¿si quitamos la primera letra, existe la palabra?
                without_first = word[1:]
                if without_first in word_set:
                    left_internal = word[0]
                
                # Hook interno derecho: ¿si quitamos la última letra, existe la palabra?
                without_last = word[:-1]
                if without_last in word_set:
                    right_internal = word[-1]
            
            # Insertar en base de datos
            cursor.execute("""
                INSERT INTO word_hooks (word, left_hooks, right_hooks, left_internal_hooks, right_internal_hooks)
                VALUES (?, ?, ?, ?, ?)
            """, (word, left_external, right_external, left_internal, right_internal))
            
            # Contar hooks
            if left_external or right_external:
                external_hooks_count += 1
            if left_internal or right_internal:
                internal_hooks_count += 1
                
            processed += 1
        
        # Confirmar transacción
        conn.commit()
        
        # Progreso
        percentage = (processed / len(all_words)) * 100
        elapsed = time.time() - start_time
        rate = processed / elapsed if elapsed > 0 else 0
        eta = (len(all_words) - processed) / rate if rate > 0 else 0
        
        log(f"⚡ {processed:6d}/{len(all_words)} ({percentage:5.1f}%) | Ext: {external_hooks_count:5d} | Int: {internal_hooks_count:5d} | ETA: {int(eta):3d}s")
    
    duration = time.time() - start_time
    
    # Verificación final
    cursor.execute("SELECT COUNT(*) FROM word_hooks")
    final_count = cursor.fetchone()[0]
    
    log("═" * 50)
    log("🎉 GENERACIÓN COMPLETA!")
    log(f"📊 Palabras procesadas: {processed}")
    log(f"🔗 Palabras con hooks externos: {external_hooks_count}")
    log(f"🔄 Palabras con hooks internos: {internal_hooks_count}")
    log(f"💾 Registros en BD: {final_count}")
    log(f"⏱️  Tiempo total: {duration:.1f}s")
    log(f"⚡ Velocidad: {processed/duration:.0f} palabras/seg")
    
    # Mostrar ejemplos
    log("\n🔍 EJEMPLOS DE HOOKS EXTERNOS:")
    cursor.execute("""
        SELECT word, left_hooks, right_hooks 
        FROM word_hooks 
        WHERE length(left_hooks) > 2 AND length(right_hooks) > 2
        ORDER BY length(left_hooks) + length(right_hooks) DESC 
        LIMIT 5
    """)
    
    for word, left, right in cursor.fetchall():
        log(f"   {left.lower()}{word}{right.lower()}")
    
    log("\n🔍 EJEMPLOS DE HOOKS INTERNOS:")
    cursor.execute("""
        SELECT word, left_internal_hooks, right_internal_hooks
        FROM word_hooks 
        WHERE left_internal_hooks != '' OR right_internal_hooks != ''
        ORDER BY length(word) DESC 
        LIMIT 5
    """)
    
    for word, left_int, right_int in cursor.fetchall():
        examples = []
        if left_int:
            examples.append(f"[{left_int.lower()}]{word} → {word[1:]}")
        if right_int:
            examples.append(f"{word}[{right_int.lower()}] → {word[:-1]}")
        log(f"   {' | '.join(examples)}")
    
    # Archivo de completado
    completion_file = db_path.replace(".sqlite", "_HOOKS_PYTHON_COMPLETED.txt")
    with open(completion_file, 'w') as f:
        f.write(f"""🎉 HOOKS GENERATION COMPLETED! 🎉

Timestamp: {datetime.now()}
Database: {db_path}

RESULTS:
- Total words: {processed}
- External hooks: {external_hooks_count} words  
- Internal hooks: {internal_hooks_count} words
- Processing time: {duration:.1f}s
- Rate: {processed/duration:.0f} words/sec

HOOK TYPES:
1. External hooks: Letters you can ADD before/after word
2. Internal hooks: Letters you can REMOVE from start/end

ScrabbleFinder hooks database is COMPLETE!
""")
    
    conn.close()
    
    if final_count == processed:
        log(f"\n✅ ÉXITO! Todos los {final_count} registros guardados correctamente")
        log(f"📁 Archivo de completado: {completion_file}")
        log("🚀 Base de datos lista para ScrabbleFinder!")
    else:
        log(f"\n❌ ERROR: Esperaba {processed} pero encontré {final_count} registros")

if __name__ == "__main__":
    generate_hooks()