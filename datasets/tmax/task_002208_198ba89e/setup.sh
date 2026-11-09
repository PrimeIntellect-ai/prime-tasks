#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc upx-ucl
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /tmp/graph_indexer.c
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if(argc != 2) return 1;
    sqlite3 *db;
    if(sqlite3_open(argv[1], &db)) return 1;
    char *err = 0;
    sqlite3_exec(db, "DROP TABLE IF EXISTS index_stats;", 0, 0, &err);
    sqlite3_exec(db, "CREATE TABLE index_stats AS SELECT id as node_id, (SELECT count(*) FROM edges WHERE src=id OR dst=id) as degree FROM nodes;", 0, 0, &err);
    sqlite3_close(db);
    return 0;
}
EOF

gcc -O2 /tmp/graph_indexer.c -o /app/graph_indexer -lsqlite3
strip /app/graph_indexer
upx /app/graph_indexer || true
chmod +x /app/graph_indexer

cat << 'EOF' > /tmp/gen_dbs.py
import sqlite3
import os
import random

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

def make_db(path, is_evil):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY)")
    c.execute("CREATE TABLE edges (src INTEGER, dst INTEGER)")
    c.execute("CREATE TABLE index_stats (node_id INTEGER, degree INTEGER)")

    num_nodes = 10
    for i in range(1, num_nodes+1):
        c.execute("INSERT INTO nodes (id) VALUES (?)", (i,))

    for _ in range(15):
        u = random.randint(1, num_nodes)
        v = random.randint(1, num_nodes)
        c.execute("INSERT INTO edges (src, dst) VALUES (?, ?)", (u, v))

    conn.commit()

    c.execute("CREATE TEMP TABLE true_stats AS SELECT id as node_id, (SELECT count(*) FROM edges WHERE src=id OR dst=id) as degree FROM nodes")

    if is_evil:
        c.execute("INSERT INTO index_stats SELECT node_id, degree + 1 FROM true_stats")
    else:
        c.execute("INSERT INTO index_stats SELECT * FROM true_stats")

    conn.commit()
    conn.close()

for i in range(5):
    make_db(f'/app/corpus/clean/db_{i}.sqlite', False)
    make_db(f'/app/corpus/evil/db_{i}.sqlite', True)
EOF

python3 /tmp/gen_dbs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
