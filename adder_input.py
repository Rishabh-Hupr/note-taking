import sys
from noter import AddNote
from utils import log_it


input = sys.argv[1:]

def split_key_value(input):
    # split based on //// character
    log = "Received input: " + input[0]
    log_it(log)

    input = input[0]
    parts = input.split('////')
    key = parts[0].strip()
    value = parts[1].strip()
    key = key
    value = value

    log = "Stripped input: " + key + ", " + value
    log_it(log)

    return key, value

key, value = split_key_value(input)
if key and value:
    adder_notes = AddNote()
    log = "Created AddNote instance and calling add_note()"
    log_it(log)
    
    adder_notes.add_note(key, value)
    log = "Added key: " + key
    log_it(log)
log_it("-------------")
