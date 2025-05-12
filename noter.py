from notes import NotesDatabase
import sys, json, sqlite3

key = sys.argv[1]
value = sys.argv[2]

class AddNote(NotesDatabase):
    def __init__(self):
        # call the parent class constructor
        super().__init__()
    
    def add_note(self, key, value):
        # Convert non-string values to JSON
        if not isinstance(value, str):
            value = json.dumps(value)
        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            self.conn.execute('''
                INSERT OR REPLACE INTO notes (key, value, updated_at) 
                VALUES (?, ?, CURRENT_TIMESTAMP)
            ''', (key, value))
            self.conn.commit()



notes = AddNote()
notes.add_note(key, value)