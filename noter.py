from notes import NotesDatabase
import json
# amazonq-ignore-next-line
import sqlite3
from utils import log_it

class AddNote(NotesDatabase):
    def __init__(self):
        # call the parent class constructor
        super().__init__()
    
    def add_note(self, key, value):
        key = str(key)
        value = str(value)
        from contextlib import closing
        with closing(sqlite3.connect(self.db_path)) as self.conn:
            log = "Calling insert on database"
            log_it(log)

            self.conn.execute('''
                INSERT OR REPLACE INTO notes (key, value, created_at) 
                VALUES (?, ?, CURRENT_TIMESTAMP)
            ''', (key, value))
            self.conn.commit()



########### NO Execution of below ############
'''
    When you want to update the schema for notes_fts
    to change any full text based search functionality
    currently supports 'Prefix' param only
'''
# notes_obj = NotesDatabase()
# notes_obj.rebuild_fts_table()
#############################################
