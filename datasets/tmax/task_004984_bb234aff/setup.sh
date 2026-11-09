#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random
from datetime import datetime, timedelta

conn = sqlite3.connect('/home/user/backup_metadata.db')
c = conn.cursor()
c.execute('CREATE TABLE chunks (id INTEGER PRIMARY KEY, size INTEGER, timestamp DATETIME)')
c.execute('CREATE TABLE chunk_dependencies (parent_id INTEGER, child_id INTEGER)')

chunk_id = 1
# Create 100 chains of length 500
for chain in range(100):
    parent = None
    for depth in range(500):
        size = random.randint(10, 100)
        ts = datetime.now() - timedelta(days=random.randint(0, 100))
        c.execute('INSERT INTO chunks (id, size, timestamp) VALUES (?, ?, ?)', (chunk_id, size, ts.isoformat()))
        if parent is not None:
            c.execute('INSERT INTO chunk_dependencies (parent_id, child_id) VALUES (?, ?)', (parent, chunk_id))
        parent = chunk_id
        chunk_id += 1

conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py

    # Create the slow binary
    mkdir -p /app
    cat << 'EOF' > /tmp/chunk_verifier.c
#include <stdio.h>
#include <sqlite3.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    sqlite3 *db;
    if (sqlite3_open(argv[1], &db)) return 1;

    const char *query = 
        "WITH RECURSIVE "
        "paths(id, total_size) AS ("
        "  SELECT id, size FROM chunks WHERE id NOT IN (SELECT child_id FROM chunk_dependencies) "
        "  UNION ALL "
        "  SELECT c.id, p.total_size + c.size "
        "  FROM chunks c "
        "  JOIN chunk_dependencies cd ON c.id = cd.child_id "
        "  JOIN paths p ON p.id = cd.parent_id"
        ") "
        "SELECT MAX(total_size) FROM paths;";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, 0) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            printf("%d\n", sqlite3_column_int(stmt, 0));
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    usleep(2500000); // Sleep for 2.5 seconds to simulate bad performance
    return 0;
}
EOF
    gcc -O2 /tmp/chunk_verifier.c -o /app/chunk_verifier -lsqlite3
    strip /app/chunk_verifier

    chmod -R 777 /home/user
    chmod 755 /app/chunk_verifier
