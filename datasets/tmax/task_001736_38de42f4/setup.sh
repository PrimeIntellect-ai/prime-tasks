#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc make sqlite3
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > Makefile
all:
	gcc -o libcompute.so compute.c
EOF

    cat << 'EOF' > compute.c
int fast_add(int a, int b) {
    return a + b;
}
EOF

    cat << 'EOF' > schema_migration.sql
ALTER TABLE users RENAME COLUMN user_id TO account_id;
EOF

    cat << 'EOF' > db.py
import sqlite3

def init_db(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)")
    c.execute("INSERT INTO users (user_id, name) VALUES (1, 'Alice')")
    conn.commit()
    conn.close()

def apply_migration(db_path, migration_file):
    conn = sqlite3.connect(db_path)
    with open(migration_file, 'r') as f:
        conn.executescript(f.read())
    conn.commit()
    conn.close()

def get_user_id(db_path, name):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    # BUG: using user_id instead of account_id
    c.execute("SELECT user_id FROM users WHERE name = ?", (name,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None
EOF

    cat << 'EOF' > main.py
import ctypes
import os
import db

def compute_math(a, b):
    lib_path = os.path.join(os.path.dirname(__file__), 'libcompute.so')
    lib = ctypes.CDLL(lib_path)
    lib.fast_add.argtypes = [ctypes.c_int, ctypes.c_int]
    lib.fast_add.restype = ctypes.c_int
    return lib.fast_add(a, b)
EOF

    cat << 'EOF' > test_e2e.py
import os
import db
import main

def test_system():
    db_path = 'test.db'
    if os.path.exists(db_path):
        os.remove(db_path)

    db.init_db(db_path)
    db.apply_migration(db_path, 'schema_migration.sql')

    # Test DB after migration
    uid = db.get_user_id(db_path, 'Alice')
    assert uid == 1

    # Test C extension
    res = main.compute_math(10, 5)
    assert res == 15
EOF

    cat << 'EOF' > run_ci.sh
#!/bin/bash

cd /home/user/project
make clean || true
make
pytest test_e2e.py > /home/user/ci_results.log
EOF
    chmod +x run_ci.sh

    cat << 'EOF' > requirements.txt
pytest
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
