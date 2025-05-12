# amazonq-ignore-next-line
import sqlite3

class NotesDatabase:
    def __init__(self, db_path="db/notes.db"):
        self.db_path = db_path
        # Using contextlib.closing to ensure proper resource management
        # This helps in automatically closing the connection when it's no longer needed
        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            # Enable foreign keys and other optimizations
            self.conn.execute("PRAGMA foreign_keys = ON")
            self.conn.execute("PRAGMA journal_mode = WAL")
            
            # Create tables if they don't exist
            self._create_tables()
    
    def _create_tables(self):
        # Main notes table
        self.conn.execute('''
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY,
                key TEXT UNIQUE NOT NULL,
                value TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Full-text search table
        # The hyphen in column names is causing the parse error
        # SQLite column names should not contain hyphens
        # Changed keyfts to key_fts and valuefts to value_fts
        self.conn.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts 
            USING FTS5(key_fts, value_fts, content='notes', content_rowid='id')
        ''')
        
        # Create triggers to keep FTS index updated
        self.conn.executescript('''
            CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
                INSERT INTO notes_fts(rowid, key_fts, value_fts) VALUES (new.id, new.key_fts, new.value_fts);
            END;
            
            CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, rowid, key_fts, value_fts) VALUES('delete', old.id, old.key_fts, old.value_fts);
            END;
            
            CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, rowid, key_fts, value_fts) VALUES('delete', old.id, old.key_fts, old.value_fts);
                INSERT INTO notes_fts(rowid, key_fts, value_fts) VALUES (new.id, new.key_fts, new.value_fts);
            END;
        ''')
        
        self.conn.commit()
