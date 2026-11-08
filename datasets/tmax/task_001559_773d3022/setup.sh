#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the SQLite DB
    sqlite3 /home/user/users.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, metadata TEXT);
INSERT INTO users (id, username, metadata) VALUES (101, 'alice', '{"status": "active", "points": 150}');
INSERT INTO users (id, username, metadata) VALUES (102, 'bob', '{"status": "inactive", "points": 0}');
INSERT INTO users (id, username, metadata) VALUES (9942, 'charlie_crash', '{"status": "active", "points": -50}');
INSERT INTO users (id, username, metadata) VALUES (104, 'david', '{"status": "active", "points": 20}');
EOF

    # 2. Create the memory dump
    head -c 1024 /dev/urandom > /home/user/memory.dump
    echo -n "FATAL_USER_ID=9942" >> /home/user/memory.dump
    head -c 512 /dev/urandom >> /home/user/memory.dump

    # 3. Create app.py
    cat << 'EOF' > /home/user/app.py
import json

def validate_user_data(metadata_str: str) -> bool:
    """Validates user metadata. Should raise ValueError if data is corrupted."""
    try:
        data = json.loads(metadata_str)
    except json.JSONDecodeError:
        return False

    # TODO: Add business logic validation here to prevent crashes
    return True
EOF

    chmod -R 777 /home/user
