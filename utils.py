import config
import os

if not os.path.exists(config.LOG_PATH):
    os.makedirs(config.LOG_PATH)

log_store = config.LOG_PATH + "/app.log"

def log_it(var):
    # write input var into app.log
    with open(log_store, "a+") as log_file:
    # prepend current timestamp in UTC to the text being logged
        from datetime import datetime, timezone
        data_to_input = str(datetime.now(timezone.utc)) + " " + var
        log_file.write(data_to_input + "\n")

def escape_string(s):
    """Escape a string to be wrapped in single quotes."""
    return s.replace("'", "\\'") if s else s