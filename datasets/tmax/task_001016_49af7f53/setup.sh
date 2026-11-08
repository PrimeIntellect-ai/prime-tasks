#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        build-essential \
        libsqlite3-dev \
        sqlite3

    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create the Python script to generate the database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/taxonomy.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes(id INTEGER PRIMARY KEY, category_group TEXT)')
c.execute('CREATE TABLE edges(parent_id INTEGER, child_id INTEGER, weight REAL)')

random.seed(42)
groups = [f'Group_{i}' for i in range(10)]
nodes = [(i, random.choice(groups)) for i in range(1, 15001)]
c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)

edges = []
for i in range(2, 15001):
    parent = random.randint(1, i - 1)
    weight = round(random.uniform(0.1, 10.0), 2)
    edges.append((parent, i, weight))
c.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/gen_db.py

    # Create the legacy C tool
    cat << 'EOF' > /tmp/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>
#include <string.h>

sqlite3 *db;

double get_weight(int node_id) {
    double total = 0.0;
    sqlite3_stmt *stmt;
    const char *sql = "SELECT child_id, weight FROM edges WHERE parent_id = ?";
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    sqlite3_bind_int(stmt, 1, node_id);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int child_id = sqlite3_column_int(stmt, 0);
        double weight = sqlite3_column_double(stmt, 1);
        total += weight + get_weight(child_id);
    }
    sqlite3_finalize(stmt);
    return total;
}

typedef struct {
    int id;
    double weight;
} NodeWeight;

int compare(const void *a, const void *b) {
    double wa = ((NodeWeight*)a)->weight;
    double wb = ((NodeWeight*)b)->weight;
    if (wa < wb) return 1;
    if (wa > wb) return -1;
    return 0;
}

int main() {
    if (sqlite3_open("/home/user/taxonomy.db", &db) != SQLITE_OK) return 1;

    const char *g_sql = "SELECT DISTINCT category_group FROM nodes ORDER BY category_group";
    sqlite3_stmt *g_stmt;
    sqlite3_prepare_v2(db, g_sql, -1, &g_stmt, NULL);

    char groups[20][50];
    int num_groups = 0;
    while (sqlite3_step(g_stmt) == SQLITE_ROW) {
        strcpy(groups[num_groups++], (const char*)sqlite3_column_text(g_stmt, 0));
    }
    sqlite3_finalize(g_stmt);

    for (int i = 0; i < num_groups; i++) {
        const char *n_sql = "SELECT id FROM nodes WHERE category_group = ?";
        sqlite3_stmt *n_stmt;
        sqlite3_prepare_v2(db, n_sql, -1, &n_stmt, NULL);
        sqlite3_bind_text(n_stmt, 1, groups[i], -1, SQLITE_STATIC);

        NodeWeight *nw = malloc(15000 * sizeof(NodeWeight));
        int count = 0;
        while (sqlite3_step(n_stmt) == SQLITE_ROW) {
            int id = sqlite3_column_int(n_stmt, 0);
            nw[count].id = id;
            nw[count].weight = get_weight(id);
            count++;
        }
        sqlite3_finalize(n_stmt);

        qsort(nw, count, sizeof(NodeWeight), compare);

        for (int j = 0; j < 3 && j < count; j++) {
            printf("%s,%d,%.2f,%d\n", groups[i], nw[j].id, nw[j].weight, j + 1);
        }
        free(nw);
    }

    sqlite3_close(db);
    return 0;
}
EOF

    gcc -O3 -o /app/legacy_calc /tmp/legacy_calc.c -lsqlite3
    strip /app/legacy_calc

    chmod -R 777 /home/user
    chmod -R 777 /app
