#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev binutils
    pip3 install pytest

    mkdir -p /home/user /app

    # Generate the SQLite database
    cat << 'EOF' > /tmp/generate_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/data_lineage.db')
c = conn.cursor()
c.execute('CREATE TABLE datasets(id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE transformations(id INTEGER PRIMARY KEY, source_id INTEGER, target_id INTEGER, operation TEXT)')

for i in range(1, 5001):
    c.execute('INSERT INTO datasets (id, name) VALUES (?, ?)', (i, f'dataset_{i}'))

edges = set()
while len(edges) < 7000:
    src = random.randint(1, 4999)
    tgt = random.randint(src + 1, 5000)
    edges.add((src, tgt))

for i, (src, tgt) in enumerate(edges, 1):
    c.execute('INSERT INTO transformations (id, source_id, target_id, operation) VALUES (?, ?, ?, ?)', (i, src, tgt, 'transform'))

conn.commit()
conn.close()
EOF
    python3 /tmp/generate_db.py

    # Create the legacy C program
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <db_path> <dataset_id>\n", argv[0]);
        return 1;
    }
    sqlite3 *db;
    if (sqlite3_open(argv[1], &db) != SQLITE_OK) {
        fprintf(stderr, "Cannot open database\n");
        return 1;
    }
    const char *query = 
        "WITH RECURSIVE lineage AS ("
        "  SELECT id, name, 0 as distance FROM datasets WHERE id = ? "
        "  UNION ALL "
        "  SELECT d.id, d.name, l.distance + 1 "
        "  FROM lineage l "
        "  JOIN transformations t ON l.id = t.target_id "
        "  JOIN datasets d ON t.source_id = d.id "
        ") "
        "SELECT id, name, MIN(distance) as dist FROM lineage GROUP BY id ORDER BY dist ASC, id ASC;";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, query, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Failed to prepare statement\n");
        return 1;
    }
    sqlite3_bind_int(stmt, 1, atoi(argv[2]));

    printf("[\n");
    int first = 1;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (!first) {
            printf(",\n");
        }
        first = 0;
        printf("  {\"id\": %d, \"name\": \"%s\", \"distance\": %d}", 
            sqlite3_column_int(stmt, 0),
            sqlite3_column_text(stmt, 1),
            sqlite3_column_int(stmt, 2));
    }
    printf("\n]\n");

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF
    gcc -O2 -o /app/legacy_lineage /tmp/legacy.c -lsqlite3
    strip -s /app/legacy_lineage

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
