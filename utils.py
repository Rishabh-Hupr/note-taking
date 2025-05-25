def log_it(var):
    # write input var into app.log
    with open("./note-taking/app.log", "a+") as log_file:
    # prepend current timestamp in UTC to the text being logged
        from datetime import datetime, timezone
        var = str(datetime.now(timezone.utc)) + " " + var
        log_file.write(var + "\n")

def escape_string(s):
    """Escape a string to be wrapped in single quotes."""
    return s.replace("'", "\\'") if s else s