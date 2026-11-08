#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the setup script and run it to initialize the database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/backup_meta.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    db_name TEXT,
    backup_type TEXT,
    timestamp INTEGER,
    file_path TEXT
)
''')

cursor.execute('''
CREATE TABLE dependencies (
    backup_id INTEGER,
    depends_on_id INTEGER
)
''')

# Insert backups
backups = [
    (1, 'db_alpha', 'FULL', 1690000000, '/backups/alpha_full_1.bak'),
    (2, 'db_beta', 'FULL', 1690000005, '/backups/beta_full_1.bak'),
    (3, 'db_alpha', 'INC', 1690000010, '/backups/alpha_inc_1.bak'),
    (4, 'db_gamma', 'FULL', 1690000015, '/backups/gamma_full_1.bak'),
    (5, 'db_alpha', 'INC', 1690000020, '/backups/alpha_inc_2.bak'),
    (6, 'db_beta', 'INC', 1690000025, '/backups/beta_inc_1.bak'),
    (7, 'db_alpha', 'INC', 1690000040, '/backups/alpha_inc_3.bak'),
    (8, 'db_alpha', 'INC', 1690000060, '/backups/alpha_inc_4.bak') # After target
]

cursor.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", backups)

# Insert dependencies
deps = [
    (3, 1), # alpha_inc_1 depends on alpha_full_1
    (5, 3), # alpha_inc_2 depends on alpha_inc_1
    (5, 2), # alpha_inc_2 ALSO depends on beta_full_1 (cross-db)
    (6, 2), # beta_inc_1 depends on beta_full_1
    (7, 5), # alpha_inc_3 depends on alpha_inc_2
    (7, 4), # alpha_inc_3 ALSO depends on gamma_full_1
    (8, 7)  # alpha_inc_4 depends on alpha_inc_3
]

cursor.executemany("INSERT INTO dependencies VALUES (?, ?)", deps)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
