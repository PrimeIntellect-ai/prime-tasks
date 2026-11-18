#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create Python script to generate the database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/topology.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, base_weight REAL)')
c.execute('CREATE TABLE edges (source_id INTEGER, target_id INTEGER, latency REAL)')

for i in range(1, 10001):
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (i, f'Node_{i}', random.uniform(1.0, 100.0)))

for i in range(1, 10000):
    num_edges = random.randint(0, 3)
    for _ in range(num_edges):
        target = random.randint(i + 1, 10000)
        c.execute('INSERT INTO edges VALUES (?, ?, ?)', (i, target, random.uniform(0.1, 10.0)))

conn.commit()
conn.close()
EOF

    python3 /tmp/gen_db.py

    # Create C program for legacy binary
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

double get_flow(sqlite3 *db, int current_node, double current_latency) {
    double total_flow = 0.0;
    char query[256];
    sprintf(query, "SELECT target_id, latency FROM edges WHERE source_id = %d", current_node);
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) != SQLITE_OK) return 0.0;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int target_id = sqlite3_column_int(stmt, 0);
        double latency = sqlite3_column_double(stmt, 1);

        char q2[256];
        sprintf(q2, "SELECT base_weight FROM nodes WHERE id = %d", target_id);
        sqlite3_stmt *stmt2;
        double weight = 0.0;
        if (sqlite3_prepare_v2(db, q2, -1, &stmt2, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt2) == SQLITE_ROW) {
                weight = sqlite3_column_double(stmt2, 0);
            }
            sqlite3_finalize(stmt2);
        }

        double path_latency = current_latency + latency;
        total_flow += weight / path_latency;
        total_flow += get_flow(db, target_id, path_latency);
    }
    sqlite3_finalize(stmt);
    return total_flow;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int root = atoi(argv[1]);
    sqlite3 *db;
    if (sqlite3_open("/home/user/topology.db", &db)) return 1;
    double res = get_flow(db, root, 0.0);
    printf("%.4f\n", res);
    sqlite3_close(db);
    return 0;
}
EOF

    gcc -O2 /tmp/legacy.c -o /app/legacy_flow_calc -lsqlite3
    strip /app/legacy_flow_calc
    chmod +x /app/legacy_flow_calc

    # Cleanup
    rm /tmp/gen_db.py /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
