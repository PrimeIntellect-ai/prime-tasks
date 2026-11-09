#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/project_legacy
    cat << 'EOF' > /home/user/project_legacy/data_reader.py
def get_latest_data():
    return {"status": "real"}
EOF

    python3 -c '
import sqlite3
conn = sqlite3.connect("/home/user/project_legacy/db.sqlite3")
c = conn.cursor()
c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, app_version TEXT)")
users = [
    (1, "Alice", "1.0.5"),
    (2, "Bob", "2.0.9"),
    (3, "Charlie", "2.1.0"),
    (4, "Dave", "2.2.0-rc1"),
    (5, "Eve", "1.9.99"),
    (6, "Frank", "3.0.0")
]
c.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
conn.commit()
conn.close()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
