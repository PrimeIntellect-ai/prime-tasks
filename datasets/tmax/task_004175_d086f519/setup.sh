#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/api_db.sqlite"

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE routes (id INTEGER PRIMARY KEY, path TEXT, condition TEXT)")
cursor.execute("CREATE TABLE depends_on (route_id INTEGER, depends_on_id INTEGER)")

routes_data = [
    (1, "/api/users", 'header.auth = "valid"'),
    (2, "/api/users/admin", 'param.role = "admin" AND header.auth = "valid"'),
    (3, "/api/posts", 'param.draft = "false" OR header.auth = "valid"'),
    (4, "/api/comments", 'param.length > 0 AND param.length < 500')
]
cursor.executemany("INSERT INTO routes VALUES (?, ?, ?)", routes_data)

depends_on_data = [
    (2, 1),
    (3, 1),
    (4, 3),
    (1, 4)
]
cursor.executemany("INSERT INTO depends_on VALUES (?, ?)", depends_on_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
