from notes import NotesDatabase
import json
# amazonq-ignore-next-line
import sqlite3



class FetchNote(NotesDatabase):
    def get_note(self, key):
        result = cursor = None

        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            with closing(self.conn.cursor()) as cursor:
                cursor.execute("SELECT value FROM notes WHERE key = ?", (key,))
                result = cursor.fetchone()
        if result:
            try:
                return json.loads(result[0])
            except json.JSONDecodeError:
                return result[0]
        return None
    
    def search_notes(self, query):
        cursor = None
        results = {}
        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            cursor = self.conn.execute('''
                SELECT notes.key, notes.value FROM notes 
                JOIN notes_fts ON notes.id = notes_fts.rowid
                WHERE notes_fts MATCH ?
            ''', (f'key:{query}*',))
        
            for key, value in cursor.fetchall():
                try:
                    results[key] = json.loads(value)
                except json.JSONDecodeError:
                    results[key] = value
        return results

key_to_search = input("Enter key to search: ")
fetcher = FetchNote()
print(fetcher.search_notes(key_to_search))