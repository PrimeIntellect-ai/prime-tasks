#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install system dependencies
apt-get install -y redis-server sqlite3 libsqlite3-dev

# Create app directory
mkdir -p /app

# Create SQLite database with schema
sqlite3 /app/warehouse.db <<'EOF'
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    status TEXT,
    priority INTEGER,
    created_at INTEGER
);
CREATE INDEX idx_status ON users(status);
EOF

# Insert data
python3 -c "
import sqlite3, random
random.seed(42)
conn = sqlite3.connect('/app/warehouse.db')
c = conn.cursor()
for i in range(1, 4001):
    status = 'ACTIVE' if i % 2 == 0 else 'INACTIVE'
    priority = random.randint(1, 100)
    created_at = 1600000000 + i * 10
    c.execute('INSERT INTO users (id, name, status, priority, created_at) VALUES (?, ?, ?, ?, ?)', 
              (i, f'User{i}', status, priority, created_at))
conn.commit()
"

# Corrupt the index
sqlite3 /app/warehouse.db <<'EOF'
PRAGMA writable_schema = 1;
UPDATE sqlite_master SET sql = 'CREATE INDEX idx_status ON users(status)' WHERE name = 'idx_status';
PRAGMA writable_schema = 0;
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /app/warehouse.db
chmod 644 /app/warehouse.db
chmod -R 777 /home/user
