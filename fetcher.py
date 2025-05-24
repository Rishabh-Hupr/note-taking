from notes import NotesDatabase
import json
# amazonq-ignore-next-line
import sqlite3
import sys
from utils import log_it, escape_string

class FetchNote(NotesDatabase):
    # def get_note(self, key):
    #     result = cursor = None

    #     from contextlib import closing
    #     with closing(sqlite3.connect(self.db_path)) as self.conn:
    #         with closing(self.conn.cursor()) as cursor:
    #             cursor.execute("SELECT value FROM notes WHERE key = ?", (key,))
    #             result = cursor.fetchone()
    #     if result:
    #         try:
    #             return json.loads(result[0])
    #         except json.JSONDecodeError:
    #             return result[0]
    #     return None
    
    def show_db(self):
        cursor = None
        result = {}
        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            cursor = self.conn.execute("SELECT key, value, created_at FROM notes")
            
            for key, value, ts in cursor.fetchall():
                log_it(str(key + " " + value + " " + ts))
                try:
                    result[key] = value
                except Exception as e:
                    log_it("fetcher.py: show_db(): "+ str(e))
                
                try:
                    result[ts] = ts
                except Exception as e:
                    log_it("fetcher.py: show_db(): "+ str(e))

        return result


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
    

try:
    key = sys.argv[1]
    log = "Received key: " + key
    log_it(log)

    fetcher = FetchNote()
    rs = fetcher.search_notes(key)
    if rs:
        print(rs)
        log = "Fetched key: " + key
        log_it(log)
        log_it("-------------")
except:
    log_it("fetcher.py: No key provided")
    fetcher = FetchNote()
    print(fetcher.show_db())
    log_it("-------------")