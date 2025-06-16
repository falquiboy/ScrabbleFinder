#!/usr/bin/env python3
"""
ScrabbleFinder Hooks Generator
Generates hooks database for Spanish Scrabble words.

Hooks Types:
- External Left: Letters that can be added to the left of a word
- External Right: Letters that can be added to the right of a word  
- Internal Left: If removing first letter creates a valid word
- Internal Right: If removing last letter creates a valid word

Usage: python generate_hooks.py <words_db_path> <output_hooks_db_path>
"""

import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path

class HooksGenerator:
    def __init__(self, words_db_path: str, hooks_db_path: str):
        self.words_db_path = Path(words_db_path)
        self.hooks_db_path = Path(hooks_db_path)
        self.spanish_alphabet = list("ABCDEFGHIJKLMNÑOPQRSTUVWXYZÇKW")  # Include digraph chars
        
        # Validate input database exists
        if not self.words_db_path.exists():
            raise FileNotFoundError(f"Words database not found: {words_db_path}")
        
        self.log_file = self.hooks_db_path.with_suffix('.log')
        
    def log(self, message: str):
        """Log message to console and file"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] {message}"
        print(message)
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(log_message + '\n')
    
    def setup_hooks_database(self):
        """Create and setup the hooks database"""
        self.log("🔧 Setting up hooks database...")
        
        # Remove existing database
        if self.hooks_db_path.exists():
            self.hooks_db_path.unlink()
            self.log(f"📁 Removed existing database: {self.hooks_db_path}")
        
        # Create new database
        conn = sqlite3.connect(self.hooks_db_path)
        cursor = conn.cursor()
        
        # Create hooks table
        cursor.execute('''
            CREATE TABLE word_hooks (
                word TEXT PRIMARY KEY,
                left_external TEXT NOT NULL DEFAULT '',
                right_external TEXT NOT NULL DEFAULT '',
                left_internal TEXT NOT NULL DEFAULT '',
                right_internal TEXT NOT NULL DEFAULT '',
                has_external_hooks INTEGER NOT NULL DEFAULT 0,
                has_internal_hooks INTEGER NOT NULL DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        ''')
        
        # Create indices for performance
        cursor.execute('CREATE INDEX idx_word_hooks_word ON word_hooks(word);')
        cursor.execute('CREATE INDEX idx_word_hooks_external ON word_hooks(has_external_hooks);')
        cursor.execute('CREATE INDEX idx_word_hooks_internal ON word_hooks(has_internal_hooks);')
        
        # Optimize database
        cursor.execute('PRAGMA journal_mode=WAL;')
        cursor.execute('PRAGMA synchronous=NORMAL;')
        cursor.execute('PRAGMA cache_size=50000;')
        cursor.execute('PRAGMA temp_store=MEMORY;')
        
        conn.commit()
        conn.close()
        
        self.log("✅ Hooks database created successfully")
    
    def load_words(self) -> set:
        """Load all words from the words database"""
        self.log("📚 Loading words from database...")
        
        conn = sqlite3.connect(self.words_db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT DISTINCT word FROM words")
        words = {row[0].upper() for row in cursor.fetchall()}
        
        conn.close()
        
        self.log(f"✅ Loaded {len(words)} unique words")
        return words
    
    def generate_hooks_for_word(self, word: str, word_set: set) -> dict:
        """Generate all hooks for a single word"""
        hooks = {
            'word': word,
            'left_external': '',
            'right_external': '',
            'left_internal': '',
            'right_internal': '',
            'has_external_hooks': 0,
            'has_internal_hooks': 0
        }
        
        # External hooks (extensions)
        left_external_chars = []
        right_external_chars = []
        
        for letter in self.spanish_alphabet:
            # Left external: can we add this letter to the left?
            extended_left = letter + word
            if extended_left in word_set:
                left_external_chars.append(letter)
            
            # Right external: can we add this letter to the right?
            extended_right = word + letter
            if extended_right in word_set:
                right_external_chars.append(letter)
        
        hooks['left_external'] = ''.join(sorted(left_external_chars))
        hooks['right_external'] = ''.join(sorted(right_external_chars))
        hooks['has_external_hooks'] = 1 if (left_external_chars or right_external_chars) else 0
        
        # Internal hooks (reductions) - only for words longer than 2 characters
        if len(word) > 2:
            # Left internal: remove first letter
            without_first = word[1:]
            if without_first in word_set:
                hooks['left_internal'] = word[0]
                hooks['has_internal_hooks'] = 1
            
            # Right internal: remove last letter
            without_last = word[:-1]
            if without_last in word_set:
                hooks['right_internal'] = word[-1]
                hooks['has_internal_hooks'] = 1
        
        return hooks
    
    def generate_all_hooks(self):
        """Generate hooks for all words"""
        self.log("🚀 Starting hooks generation...")
        self.log("=" * 60)
        
        start_time = time.time()
        
        # Load words
        word_set = self.load_words()
        all_words = sorted(word_set, key=lambda x: (len(x), x))
        
        # Setup database
        self.setup_hooks_database()
        
        # Process in batches
        batch_size = 1000
        total_words = len(all_words)
        total_batches = (total_words + batch_size - 1) // batch_size
        
        conn = sqlite3.connect(self.hooks_db_path)
        cursor = conn.cursor()
        
        # Prepare batch insert
        insert_sql = '''
            INSERT INTO word_hooks 
            (word, left_external, right_external, left_internal, right_internal, 
             has_external_hooks, has_internal_hooks)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        '''
        
        total_processed = 0
        total_with_external = 0
        total_with_internal = 0
        
        self.log("📊 Processing batches...")
        self.log("Batch | Processed | External | Internal | Progress | ETA")
        self.log("-" * 60)
        
        for batch_num in range(total_batches):
            batch_start = batch_num * batch_size
            batch_end = min(batch_start + batch_size, total_words)
            batch_words = all_words[batch_start:batch_end]
            
            batch_data = []
            batch_external = 0
            batch_internal = 0
            
            for word in batch_words:
                hooks = self.generate_hooks_for_word(word, word_set)
                
                batch_data.append((
                    hooks['word'],
                    hooks['left_external'],
                    hooks['right_external'],
                    hooks['left_internal'],
                    hooks['right_internal'],
                    hooks['has_external_hooks'],
                    hooks['has_internal_hooks']
                ))
                
                if hooks['has_external_hooks']:
                    batch_external += 1
                if hooks['has_internal_hooks']:
                    batch_internal += 1
            
            # Insert batch
            cursor.executemany(insert_sql, batch_data)
            conn.commit()
            
            # Update totals
            total_processed += len(batch_words)
            total_with_external += batch_external
            total_with_internal += batch_internal
            
            # Progress report
            elapsed = time.time() - start_time
            progress = (total_processed / total_words) * 100
            if total_processed > 0:
                rate = total_processed / elapsed
                remaining_time = (total_words - total_processed) / rate if rate > 0 else 0
                eta = f"{remaining_time/60:.1f}m" if remaining_time > 60 else f"{remaining_time:.0f}s"
            else:
                eta = "N/A"
            
            self.log(f"  {batch_num+1:3d} | {total_processed:8d} | {total_with_external:8d} | {total_with_internal:8d} | {progress:6.1f}% | {eta}")
        
        conn.close()
        
        # Final statistics
        duration = time.time() - start_time
        self.log("-" * 60)
        self.log("🎉 HOOKS GENERATION COMPLETED!")
        self.log(f"📊 FINAL STATISTICS:")
        self.log(f"   • Total words processed: {total_processed:,}")
        self.log(f"   • Words with external hooks: {total_with_external:,}")
        self.log(f"   • Words with internal hooks: {total_with_internal:,}")
        self.log(f"   • Total time: {duration/60:.1f} minutes")
        self.log(f"   • Processing rate: {total_processed/duration:.0f} words/sec")
        
        # Show samples
        self.show_sample_hooks()
        
        self.log(f"✅ Hooks database created: {self.hooks_db_path}")
        self.log(f"📝 Log file: {self.log_file}")
    
    def show_sample_hooks(self):
        """Show sample hooks for verification"""
        self.log("\n🔍 SAMPLE HOOKS:")
        
        conn = sqlite3.connect(self.hooks_db_path)
        cursor = conn.cursor()
        
        # Sample external hooks
        cursor.execute('''
            SELECT word, left_external, right_external 
            FROM word_hooks 
            WHERE has_external_hooks = 1 
            ORDER BY LENGTH(word), word 
            LIMIT 10
        ''')
        
        self.log("External hooks examples:")
        for word, left, right in cursor.fetchall():
            display = f"{left.lower()}{word}{right.lower()}" if (left or right) else word
            self.log(f"   {word} → {display}")
        
        # Sample internal hooks
        cursor.execute('''
            SELECT word, left_internal, right_internal 
            FROM word_hooks 
            WHERE has_internal_hooks = 1 
            ORDER BY LENGTH(word) DESC, word 
            LIMIT 10
        ''')
        
        self.log("Internal hooks examples:")
        for word, left, right in cursor.fetchall():
            parts = []
            if left:
                parts.append(f"[{left.lower()}]{word[1:]}")
            if right:
                parts.append(f"{word[:-1]}[{right.lower()}]")
            display = " / ".join(parts) if parts else word
            self.log(f"   {word} → {display}")
        
        conn.close()


def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_hooks.py <words_db_path> <output_hooks_db_path>")
        print("Example: python generate_hooks.py Resources/scrabble_words.sqlite Resources/scrabble_hooks.sqlite")
        sys.exit(1)
    
    words_db_path = sys.argv[1]
    hooks_db_path = sys.argv[2]
    
    try:
        generator = HooksGenerator(words_db_path, hooks_db_path)
        generator.generate_all_hooks()
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()