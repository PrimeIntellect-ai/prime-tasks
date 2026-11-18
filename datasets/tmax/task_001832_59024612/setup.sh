#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import json

logs = [
    # Window 10:00 - Top should be fr-FR, error.network (count 3)
    {"timestamp": "2023-10-15T10:05:00Z", "event": "MISSING_LOC", "key": "error.network", "locale": "fr-FR"},
    {"timestamp": "2023-10-15T10:15:30Z", "event": "MISSING_LOC", "key": "error.network", "locale": "fr-FR"},
    {"timestamp": "2023-10-15T10:45:10Z", "event": "MISSING_LOC", "key": "error.network", "locale": "fr-FR"},
    {"timestamp": "2023-10-15T10:20:00Z", "event": "MISSING_LOC", "key": "nav.home", "locale": "es-ES"},
    {"timestamp": "2023-10-15T10:55:00Z", "event": "MISSING_LOC", "key": "nav.home", "locale": "es-ES"},

    # Window 11:00 - Tie for top (count 2). Tiebreaker: es-ES comes before pt-BR.
    {"timestamp": "2023-10-15T11:01:00Z", "event": "MISSING_LOC", "key": "button.save", "locale": "pt-BR"},
    {"timestamp": "2023-10-15T11:59:59Z", "event": "MISSING_LOC", "key": "button.save", "locale": "pt-BR"},
    {"timestamp": "2023-10-15T11:10:00Z", "event": "MISSING_LOC", "key": "button.cancel", "locale": "es-ES"},
    {"timestamp": "2023-10-15T11:40:00Z", "event": "MISSING_LOC", "key": "button.cancel", "locale": "es-ES"},
    {"timestamp": "2023-10-15T11:30:00Z", "event": "MISSING_LOC", "key": "error.unknown", "locale": "de-DE"},

    # Window 12:00 - Top should be de-DE, error.unknown (count 4)
    {"timestamp": "2023-10-15T12:05:00Z", "event": "MISSING_LOC", "key": "error.unknown", "locale": "de-DE"},
    {"timestamp": "2023-10-15T12:15:00Z", "event": "MISSING_LOC", "key": "error.unknown", "locale": "de-DE"},
    {"timestamp": "2023-10-15T12:25:00Z", "event": "MISSING_LOC", "key": "error.unknown", "locale": "de-DE"},
    {"timestamp": "2023-10-15T12:35:00Z", "event": "MISSING_LOC", "key": "error.unknown", "locale": "de-DE"},
    {"timestamp": "2023-10-15T12:01:00Z", "event": "MISSING_LOC", "key": "button.save", "locale": "es-ES"},
]

with open("/home/user/loc_errors.jsonl", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")
EOF

    python3 /tmp/setup_logs.py
    rm /tmp/setup_logs.py

    chmod -R 777 /home/user
