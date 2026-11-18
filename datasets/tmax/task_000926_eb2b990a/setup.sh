#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio
    espeak -w /app/incident_audio.wav "The issue only affects backups where the environment is set to production and the retention policy is exactly thirty days."

    # Database setup
    cat << 'EOF' > /app/setup_db.py
import sqlite3

conn = sqlite3.connect('/app/backups.db')
c = conn.cursor()
c.execute('''CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT, environment TEXT)''')
c.execute('''CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, size INTEGER, status TEXT, retention_days INTEGER)''')
c.execute('''CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER)''')

# insert servers
servers = [
    (1, 'core-db', 'production'),
    (2, 'app-server-1', 'production'),
    (3, 'app-server-2', 'staging'),
    (4, 'cache-server', 'production'),
    (5, 'analytics-db', 'production'),
    (6, 'web-server', 'production')
]
c.executemany("INSERT INTO servers VALUES (?,?,?)", servers)

# insert dependencies
deps = [
    (2, 1), # app-server-1 depends on core-db
    (3, 1), # app-server-2 depends on core-db
    (4, 2), # cache-server depends on app-server-1
    (5, 4), # analytics-db depends on cache-server (3 hops from core-db)
    (6, 1)
]
c.executemany("INSERT INTO dependencies VALUES (?,?)", deps)

# insert backups
backups = [
    (1, 1, 1000, 'SUCCESS', 30),
    (2, 2, 2000, 'SUCCESS', 30),
    (3, 3, 3000, 'SUCCESS', 30), # staging
    (4, 4, 4000, 'SUCCESS', 30),
    (5, 5, 5000, 'SUCCESS', 30), # 3 hops
    (6, 6, 6000, 'SUCCESS', 30),
    (7, 1, 7000, 'SUCCESS', 7),  # wrong retention
    (8, 2, 8000, 'FAILED', 30),  # failed
    (9, 1, 9000, 'SUCCESS', 30),
    (10, 2, 10000, 'SUCCESS', 30),
    (11, 4, 11000, 'SUCCESS', 30),
    (12, 6, 12000, 'SUCCESS', 30),
    (13, 1, 13000, 'SUCCESS', 30),
    (14, 2, 14000, 'SUCCESS', 30),
    (15, 4, 15000, 'SUCCESS', 30),
    (16, 6, 16000, 'SUCCESS', 30),
    (17, 1, 17000, 'SUCCESS', 30),
    (18, 2, 18000, 'SUCCESS', 30),
]
c.executemany("INSERT INTO backups VALUES (?,?,?,?,?)", backups)

conn.commit()
conn.close()
EOF
    python3 /app/setup_db.py

    # Buggy SQL
    cat << 'EOF' > /app/generate_report.sql
SELECT b.id, s.name, b.size 
FROM backups b, servers s
WHERE b.status = 'SUCCESS'
ORDER BY b.size DESC
LIMIT 10;
EOF

    # Corpus setup
    cat << 'EOF' > /app/setup_corpus.py
import json
import hashlib

def write_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f)

def md5(s):
    return hashlib.md5(s.encode()).hexdigest()

# Clean
c1 = {"data": "backup1", "checksum": md5("backup1"), "status": "SUCCESS"}
c2 = {"data": "backup2", "checksum": md5("backup2"), "status": "SUCCESS"}
write_json('/app/corpus/clean/1.json', c1)
write_json('/app/corpus/clean/2.json', c2)

# Evil
e1 = {"data": "backup3", "checksum": "badhash", "status": "SUCCESS"}
e2 = {"data": "backup4", "checksum": md5("backup4"), "status": ["FAILED", "SUCCESS"]}
write_json('/app/corpus/evil/1.json', e1)
write_json('/app/corpus/evil/2.json', e2)
EOF
    python3 /app/setup_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
