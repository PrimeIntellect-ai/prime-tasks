#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/architecture.db')
c = conn.cursor()

c.execute("CREATE TABLE entities (id TEXT PRIMARY KEY, type TEXT, is_pii INTEGER, region TEXT)")
c.execute("CREATE TABLE relations (source TEXT, relation TEXT, target TEXT)")

entities = [
    ('user_ext_1', 'ExternalUser', 0, 'US'),
    ('user_ext_2', 'ExternalUser', 0, 'EU'),
    ('user_int_1', 'InternalUser', 0, 'US'),
    ('role_web', 'Role', 0, 'US'),
    ('role_admin', 'Role', 0, 'US'),
    ('svc_frontend', 'Service', 0, 'US'),
    ('svc_backend', 'Service', 0, 'US'),
    ('db_public', 'Database', 0, 'US'),
    ('db_users', 'Database', 1, 'US'),     # Vulnerable!
    ('db_financial', 'Database', 1, 'EU')  # Not vulnerable from ExternalUser
]

relations = [
    ('user_ext_1', 'ASSUMES', 'role_web'),
    ('user_ext_2', 'KNOWS', 'user_ext_1'), # Invalid relation type for path
    ('role_web', 'CALLS', 'svc_frontend'),
    ('svc_frontend', 'CALLS', 'svc_backend'),
    ('svc_backend', 'READS', 'db_public'),
    ('svc_backend', 'READS', 'db_users'),
    ('user_int_1', 'ASSUMES', 'role_admin'),
    ('role_admin', 'READS', 'db_financial')
]

c.executemany("INSERT INTO entities VALUES (?, ?, ?, ?)", entities)
c.executemany("INSERT INTO relations VALUES (?, ?, ?)", relations)

# Add some noise to make indexing relevant
noise_entities = [(f'noise_ent_{i}', 'Service', 0, 'US') for i in range(1000)]
noise_relations = [(f'noise_ent_{i}', 'CALLS', f'noise_ent_{i+1}') for i in range(999)]
c.executemany("INSERT INTO entities VALUES (?, ?, ?, ?)", noise_entities)
c.executemany("INSERT INTO relations VALUES (?, ?, ?)", noise_relations)

conn.commit()
conn.close()
EOF
    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
