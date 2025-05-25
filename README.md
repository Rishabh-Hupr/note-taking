# Butler
A lightning-fast, keyboard-powered note utility for macOS — store and retrieve notes or code snippets using simple key-value pairs. An ultra-minimalist knowledge base you summon with a shortcut

# SQLite-Based Note-Taking Application with Full-Text Search

A Python-based note management system that stores notes in a SQLite database with full-text search capabilities. The application provides efficient key-value storage with advanced search functionality, allowing users to find notes through keyword searches rather than exact key matches.

The system uses SQLite's FTS5 (Full-Text Search) extension to enable fast and efficient text searches across notes. It implements a robust database schema with triggers to maintain search indexes automatically and supports both exact key matches and partial text searches. The application is designed for performance and scalability, making it suitable for managing large collections of notes.

## Repository Structure
```
.
├── __init__.py              # Python package initialization
├── adder_input.py          # Handles user input for adding new notes
├── fetcher.py              # Implements note retrieval and search functionality
├── noter.py                # Contains AddNote class for note creation
├── notes.py                # Core database functionality and schema management
└── utils.py                # Utility functions for logging and string manipulation
```

## Usage Instructions
### Prerequisites
- Python 3.6 or higher
- SQLite3
- Required Python packages:
  - `sqlite3` (built-in)
  - `json` (built-in)
  - `contextlib` (built-in)

### Installation
1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Ensure SQLite is installed on your system:
```bash
# For Ubuntu/Debian
sudo apt-get install sqlite3

# For macOS
brew install sqlite3

# For Windows
# Download SQLite from https://www.sqlite.org/download.html
```

### Quick Start
1. Add a new note:
```bash
python adder_input.py "key////value"
```

2. Search for notes:
```bash
python fetcher.py "search_term"
```

3. Show all notes:
```bash
python fetcher.py
```

### More Detailed Examples
1. Adding a note with a complex value:
```bash
python adder_input.py "meeting_notes////Discussion about project timeline on 2024-01-20"
```

2. Searching notes with partial matches:
```bash
python fetcher.py "meeting"
# Returns all notes containing "meeting" in their keys
```

### Troubleshooting
Common issues and solutions:

1. Database Connection Error
```
Error: unable to open database file
```
Solution:
- Ensure the database directory exists
- Check file permissions
- Verify the database path in `notes.py`

2. Search Not Working
```
Error: no such table: notes_fts
```
Solution:
- Rebuild the FTS table using the commented code in `noter.py`
```python
notes_obj = NotesDatabase()
notes_obj.rebuild_fts_table()
```

## Data Flow
The application follows a simple data flow where notes are stored in a SQLite database with full-text search capabilities. Notes are added through the adder component and retrieved through the fetcher component.

```ascii
[User Input] -> [adder_input.py] -> [noter.py] -> [SQLite DB]
                                                      ^
                                                      |
[Search Results] <- [fetcher.py] <- [Full-Text Search]
```

Key component interactions:
1. `adder_input.py` splits input into key-value pairs
2. `noter.py` handles database insertions with automatic FTS indexing
3. `notes.py` manages database schema and connections
4. `fetcher.py` performs searches using SQLite's FTS5 capabilities
5. Triggers automatically maintain FTS indexes on insert/update/delete
6. All operations are logged through `utils.py`
7. Database uses WAL mode for better concurrent access
8. FTS5 virtual table enables prefix-based searching