#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential libsqlite3-dev sqlite3
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:${PATH}"
    chmod -R 777 /opt/rust /opt/cargo

    # Create user
    useradd -m -s /bin/bash user || true

    # Create and populate compliance.db
    python3 -c "
import sqlite3
import os

db_path = '/home/user/compliance.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''CREATE TABLE users (uid INTEGER PRIMARY KEY, username TEXT, clearance_level INTEGER)''')
cur.execute('''CREATE TABLE logs (id INTEGER PRIMARY KEY, uid INTEGER, action TEXT, target_system TEXT, timestamp INTEGER, success INTEGER)''')

cur.execute(\"INSERT INTO users VALUES (42, 'jdoe', 2)\")
cur.execute(\"INSERT INTO users VALUES (99, 'admin', 5)\")

logs = [
    (1, 42, 'READ', 'Vault A', 1600000000, 0),
    (2, 42, 'WRITE', 'Vault A', 1600000010, 0),
    (3, 42, 'READ', 'Vault A', 1600000020, 1),
    (4, 42, 'READ', 'Vault B', 1600000030, 0),
    (5, 42, 'DELETE', 'Vault C', 1600000040, 0),
    (6, 42, 'DELETE', 'Vault C', 1600000050, 0),
    (7, 42, 'DELETE', 'Vault C', 1600000060, 0),
    (8, 99, 'READ', 'Vault A', 1600000070, 0),
]

cur.executemany('INSERT INTO logs VALUES (?, ?, ?, ?, ?, ?)', logs)
conn.commit()
conn.close()
"

    # Ensure permissions
    chmod -R 777 /home/user
