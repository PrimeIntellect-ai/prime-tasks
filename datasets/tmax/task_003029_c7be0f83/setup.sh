#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace sqlite3 coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the python service script that fails due to a missing file
    cat << 'EOF' > /home/user/service.py
import sys
import ctypes

try:
    # Attempt to load a missing dependency which is the root cause
    ctypes.CDLL("/home/user/legacy_plugin.so")
except OSError:
    # Simulate an abrupt crash
    sys.exit(139)
EOF

    chmod +x /home/user/service.py

    # Create a valid SQLite database
    sqlite3 /home/user/metrics.db "CREATE TABLE events (id INTEGER PRIMARY KEY, data TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);"
    sqlite3 /home/user/metrics.db "INSERT INTO events (data) VALUES ('event_alpha'), ('event_beta'), ('event_gamma'), ('event_delta'), ('event_epsilon');"

    # Corrupt the SQLite database header slightly to force a malformed image error
    printf "CORRUPT_DB" | dd of=/home/user/metrics.db bs=1 seek=20 conv=notrunc status=none

    chmod -R 777 /home/user
