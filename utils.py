def log_it(var):
    # write input var into logs.txt
    with open("/Users/hupr/note-taking/logs.txt", "a+") as log_file:
    # prepend current timestamp to the text being logged
        from datetime import datetime
        var = str(datetime.now()) + " " + var
        log_file.write(var + "\n")

def escape_string(s):
    """Escape a string to be wrapped in single quotes."""
    return s.replace("'", "\\'") if s else s