#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/log_processor/tests

    cat << 'EOF' > /home/user/log_processor/parser.py
CURRENT_STATE = "IDLE"
PARSED_DATA = []

def parse_line(line):
    global CURRENT_STATE, PARSED_DATA
    line = line.strip()
    if line == "START":
        CURRENT_STATE = "ACTIVE"
    elif line == "STOP":
        CURRENT_STATE = "IDLE"
    elif line.startswith("DATA:") and CURRENT_STATE == "ACTIVE":
        val = line.split(":")[1].strip()
        PARSED_DATA.append(val)
EOF

    cat << 'EOF' > /home/user/log_processor/tests/test_start.py
import sys
sys.path.append("/home/user")
from log_processor import parser

def test_start_and_data():
    parser.CURRENT_STATE = "IDLE"
    parser.PARSED_DATA = []
    parser.parse_line("START")
    parser.parse_line("DATA: 100")
    assert parser.CURRENT_STATE == "ACTIVE"
    assert parser.PARSED_DATA == ["100"]
EOF

    cat << 'EOF' > /home/user/log_processor/tests/test_stop.py
import sys
sys.path.append("/home/user")
from log_processor import parser

def test_stop():
    # Because of global state, if test_start runs first, PARSED_DATA might not be empty here
    # if it wasn't manually reset. But we want the tests to be independent via classes.
    parser.parse_line("STOP")
    assert parser.CURRENT_STATE == "IDLE"
    # This will fail in the original global state setup if run after test_start without reset
    assert len(parser.PARSED_DATA) == 0 
EOF

    touch /home/user/log_processor/__init__.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
