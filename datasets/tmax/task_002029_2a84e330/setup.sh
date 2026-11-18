#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    # Create the oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/time_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long long ts = atoll(argv[1]);
    ts += 18000; // +5 hours
    time_t t = (time_t)ts;
    struct tm *tm_info = gmtime(&t);
    if (tm_info->tm_mon == 9) { // October (0-indexed)
        ts += 3600; // +1 hour
        t = (time_t)ts;
        tm_info = gmtime(&t);
    }
    char buffer[26];
    strftime(buffer, 26, "%Y-%m-%d %H:%M:%S", tm_info);
    printf("%s\n", buffer);
    return 0;
}
EOF
    gcc -o /app/time_oracle /app/time_oracle.c
    strip /app/time_oracle
    rm /app/time_oracle.c

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    # Create requirements.txt
    cat << 'EOF' > /home/user/requirements.txt
requests==2.25.1
urllib3>=1.26.0
EOF

    # Create SQLite database and WAL file, then corrupt the main DB
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os
import shutil

os.makedirs('/home/user/data', exist_ok=True)
db_path = '/home/user/data/events.db'
conn = sqlite3.connect(db_path)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE events (id INTEGER PRIMARY KEY, timestamp INTEGER, event_name TEXT);')
conn.commit()

conn.execute('INSERT INTO events (timestamp, event_name) VALUES (1600000000, "event_1");')
conn.execute('INSERT INTO events (timestamp, event_name) VALUES (1600000001, "event_2");')
conn.execute('INSERT INTO events (timestamp, event_name) VALUES (1600000002, "event_3");')
conn.execute('INSERT INTO events (timestamp, event_name) VALUES (1600000003, "event_4");')
conn.execute('INSERT INTO events (timestamp, event_name) VALUES (1600000004, "event_5");')
conn.commit()

# Copy files while connection is open to preserve WAL
shutil.copy(db_path, db_path + '.bak')
if os.path.exists(db_path + '-wal'):
    shutil.copy(db_path + '-wal', db_path + '-wal.bak')

conn.close()

# Restore files to ensure WAL exists
shutil.move(db_path + '.bak', db_path)
if os.path.exists(db_path + '-wal.bak'):
    shutil.move(db_path + '-wal.bak', db_path + '-wal')

# Corrupt the main database file
with open(db_path, "r+b") as f:
    f.write(b'\x00' * 100)
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Set permissions
    chmod -R 777 /home/user
