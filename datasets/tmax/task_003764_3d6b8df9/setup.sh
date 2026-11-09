#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/vendor/async-log-parser-0.2.1/async_log_parser
    cat << 'EOF' > /app/vendor/async-log-parser-0.2.1/setup.py
from setuptools import setup, find_packages
setup(
    name='async-log-parser',
    version='0.2.1',
    packages=find_packages(),
    install_requires=['nonexistent-pkg==99.9.9']
)
EOF

    cat << 'EOF' > /app/vendor/async-log-parser-0.2.1/async_log_parser/__init__.py
from .core import parse_file
EOF

    cat << 'EOF' > /app/vendor/async-log-parser-0.2.1/async_log_parser/core.py
def parse_file(filepath):
    events = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            # Deliberate bug: will crash if " - " is not in line
            parts = line.split(" - ")
            if len(parts) >= 2:
                events.append({"raw": line, "timestamp": parts[0], "message": parts[1]})
            else:
                events.append({"raw": line, "timestamp": "", "message": parts[1]}) # CRASH HERE
    return events
EOF

    mkdir -p /home/user/corpora/clean /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/app_01.log
10:00:01 - [START] Task 101 started
10:00:02 - [CANCEL] Task 101 interrupted
10:00:03 - [CLEANUP] Task 101 resources released
10:00:05 - [START] Task 102 started
EOF

    cat << 'EOF' > /home/user/corpora/clean/app_02.log
11:00:01 - [START] Task 201 started
11:00:02 - [CANCEL] Task 201 interrupted
11:00:03 - [CLEANUP] Task 201 resources released
malformed line with no separator
11:00:04 - [CANCEL] Task 202 interrupted
11:00:05 - [CLEANUP] Task 202 resources released
EOF

    cat << 'EOF' > /home/user/corpora/evil/leak_01.log
12:00:01 - [CANCEL] Task 301 interrupted
12:00:02 - [CANCEL] Task 302 interrupted
12:00:03 - [CANCEL] Task 303 interrupted
12:00:04 - [CANCEL] Task 304 interrupted
12:00:05 - [CANCEL] Task 305 interrupted
12:00:06 - [CANCEL] Task 306 interrupted
12:00:07 - [CLEANUP] Task 306 resources released
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
