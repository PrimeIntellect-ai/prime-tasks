#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_env.py
import sqlite3
import json

# Create SQLite DB
conn = sqlite3.connect('/home/user/warehouse.sqlite')
c = conn.cursor()

# Obfuscated table names to require reverse engineering
c.execute('''CREATE TABLE tb_usr_dim (usr_idx INTEGER PRIMARY KEY, grp_cd TEXT)''')
c.execute('''CREATE TABLE tb_grp_ref (cd TEXT PRIMARY KEY, human_name TEXT)''')

users = [
    (101, 'A1'), (102, 'A1'), (103, 'B2'), 
    (104, 'C3'), (105, 'B2'), (106, 'A1')
]
c.executemany("INSERT INTO tb_usr_dim VALUES (?, ?)", users)

groups = [
    ('A1', 'Power Users'),
    ('B2', 'Casual Readers'),
    ('C3', 'Enterprise Admins')
]
c.executemany("INSERT INTO tb_grp_ref VALUES (?, ?)", groups)
conn.commit()
conn.close()

# Create JSON events
events = [
    {"event_type": "login", "u_id": 101},
    {"event_type": "purchase", "u_id": 101},
    {"event_type": "view", "u_id": 102},
    {"event_type": "purchase", "u_id": 102},
    {"event_type": "purchase", "u_id": 102},
    {"event_type": "purchase", "u_id": 103},
    {"event_type": "login", "u_id": 104},
    {"event_type": "purchase", "u_id": 105},
    {"event_type": "purchase", "u_id": 105},
    {"event_type": "logout", "u_id": 106}
]

with open('/home/user/raw_events.json', 'w') as f:
    json.dump(events, f)
EOF

    python3 /home/user/setup_env.py
    rm /home/user/setup_env.py

    chmod -R 777 /home/user
