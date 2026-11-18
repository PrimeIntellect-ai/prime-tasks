#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)

conn = sqlite3.connect('/home/user/graph.db')
c = conn.cursor()
c.execute('CREATE TABLE edges (src INTEGER, dst INTEGER);')

# Create a stale index to confuse the agent/optimizer
c.execute('CREATE INDEX idx_stale ON edges(dst);')

edges = set()
# Generate random edges
for _ in range(2000):
    u = random.randint(1, 100)
    v = random.randint(1, 100)
    if u != v:
        edges.add((u, v))

# Inject a heavy triangle hub at node 99
hub = 99
for i in range(101, 121):
    edges.add((hub, i))
    edges.add((i, i+100))
    edges.add((i+100, hub))

c.executemany('INSERT INTO edges VALUES (?, ?)', list(edges))
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    cat << 'EOF' > /home/user/triangle_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main() {
    sqlite3 *db;
    char *err_msg = 0;
    int rc = sqlite3_open("/home/user/graph.db", &db);

    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return 1;
    }

    // TODO: Write query plan to /home/user/query_plan.txt

    // TODO: Write actual result to /home/user/max_triangle.txt

    sqlite3_close(db);
    return 0;
}
EOF

    chmod -R 777 /home/user
