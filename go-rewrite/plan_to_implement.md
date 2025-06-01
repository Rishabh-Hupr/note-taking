## Plan

1. Write a file to create the db file and all the necessary tables and all
2. Write another file that checks if the DB exists or not
    If not, then call the first file
    If yes, then just get the connection to the db file and move on
3. Write another piece of code for fetching or putting logic
4. Hook everything with current main.go file, because that does the job of actually doing stuff from UI
5. FOR GODs sake find a way to setup keyboard shortcut globally from the code itself