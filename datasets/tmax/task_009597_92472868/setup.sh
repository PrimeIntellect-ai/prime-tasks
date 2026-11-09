#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data /home/user/output

    python3 -c "
import sqlite3

conn = sqlite3.connect('/home/user/data/legacy_system.db')
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE registry_modules (
    mod_id INTEGER PRIMARY KEY,
    mod_name TEXT NOT NULL,
    current_status TEXT NOT NULL
)
''')

cursor.execute('''
CREATE TABLE module_dependencies (
    source_mod_id INTEGER,
    target_mod_id INTEGER,
    FOREIGN KEY(source_mod_id) REFERENCES registry_modules(mod_id),
    FOREIGN KEY(target_mod_id) REFERENCES registry_modules(mod_id)
)
''')

modules = [
    (1, 'Alpha', 'active'),
    (2, 'Bravo', 'active'),
    (3, 'Charlie', 'active'),
    (4, 'Delta', 'active'),
    (5, 'Echo', 'deprecated'),
    (6, 'Foxtrot', 'active')
]
cursor.executemany('INSERT INTO registry_modules VALUES (?, ?, ?)', modules)

links = [
    (1, 2),
    (1, 3),
    (2, 3),
    (4, 3),
    (4, 2),
    (5, 3),
    (6, 1)
]
cursor.executemany('INSERT INTO module_dependencies VALUES (?, ?)', links)

conn.commit()
conn.close()
"

    chmod -R 777 /home/user
