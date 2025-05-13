from notes import NotesDatabase
import json
import sqlite3

# key = sys.argv[1]
# value = sys.argv[2]

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



########### NO Execution of below ############
'''
    When you want to update the schema for notes_fts
    to change any full text based search functionality
    currently supports 'Prefix' param only
'''
# notes_obj = NotesDatabase()
# notes_obj.rebuild_fts_table()
#############################################


key_to_add = input("Enter key to add: ")
value_to_add = input("Enter value to add: ")
if key_to_add and value_to_add:
    adder_notes = AddNote()
    adder_notes.add_note(key_to_add, value_to_add   )
    print("Added key:", key_to_add)
else:
    print("Invalid input. Please provide both key and value.")
