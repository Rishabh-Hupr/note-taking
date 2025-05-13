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

        self.conn.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts 
            USING FTS5(key, value, content='notes', content_rowid='id', prefix='2 3 4 5 6');
        ''')
        
        # Create triggers to keep FTS index updated
        self.conn.executescript('''
            CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
                INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
            END;
            
            CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
            END;
            
            CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
                INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
            END;
        ''')
        
        self.conn.commit()
    
    # Uncomment below to rebuilt the notes_fts table
    # def rebuild_fts_table(self, prefix="2 3 4 5"):
    #     from contextlib import closing
    #     with closing(sqlite3.connect(self.db_path)) as self.conn:
    #         self.conn.execute("DROP TABLE IF EXISTS notes_fts")
    #         self.conn.execute(f'''
    #             CREATE VIRTUAL TABLE notes_fts 
    #             USING FTS5(key, value, content='notes', content_rowid='id', prefix='{prefix}')
    #         ''')
    #         self.conn.executescript('''
    #             CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
    #                 INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
    #             END;

    #             CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
    #                 INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
    #             END;

    #             CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
    #                 INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
    #                 INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
    #             END;
    #         ''')
    #         self.conn.execute("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')")
    #         self.conn.commit()

