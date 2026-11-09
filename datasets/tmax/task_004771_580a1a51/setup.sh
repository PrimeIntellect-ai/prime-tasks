#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        libsqlite3-dev \
        gcc \
        espeak \
        ffmpeg

    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Create lineage.db
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/lineage.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER)')

for i in range(1, 51):
    c.execute('INSERT INTO nodes (id, name) VALUES (?, ?)', (i, f'Node_{i}'))

edges = set()
while len(edges) < 150:
    src = random.randint(1, 50)
    dst = random.randint(1, 50)
    if src != dst:
        edges.add((src, dst))

for src, dst in edges:
    weight = random.randint(1, 10)
    c.execute('INSERT INTO edges (source, target, weight) VALUES (?, ?, ?)', (src, dst, weight))

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    # Generate audio
    espeak -w /app/update_notes.wav "Source 12 connects to target 45 with weight 2. Source 45 connects to target 8 with weight 5. Source 8 connects to target 31 with weight 1."

    # Create oracle C program
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

#define MAX_NODES 1000
#define INF 1000000000

int adj[MAX_NODES][MAX_NODES];

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    int src = atoi(argv[1]);
    int dst = atoi(argv[2]);

    for(int i=0; i<MAX_NODES; i++) {
        for(int j=0; j<MAX_NODES; j++) {
            adj[i][j] = INF;
        }
    }

    sqlite3 *db;
    if (sqlite3_open("/app/lineage.db", &db) != SQLITE_OK) return 1;

    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, "SELECT source, target, weight FROM edges", -1, &stmt, NULL);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int u = sqlite3_column_int(stmt, 0);
        int v = sqlite3_column_int(stmt, 1);
        int w = sqlite3_column_int(stmt, 2);
        if (u > 0 && u < MAX_NODES && v > 0 && v < MAX_NODES) {
            if (w < adj[u][v]) adj[u][v] = w;
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    int dist[MAX_NODES];
    int prev[MAX_NODES];
    int visited[MAX_NODES];
    for(int i=0; i<MAX_NODES; i++) {
        dist[i] = INF;
        prev[i] = -1;
        visited[i] = 0;
    }

    dist[src] = 0;
    for(int i=0; i<MAX_NODES; i++) {
        int u = -1;
        for(int j=0; j<MAX_NODES; j++) {
            if (!visited[j] && (u == -1 || dist[j] < dist[u])) {
                u = j;
            }
        }
        if (u == -1 || dist[u] == INF) break;
        visited[u] = 1;

        for(int v=0; v<MAX_NODES; v++) {
            if (adj[u][v] != INF) {
                if (dist[u] + adj[u][v] < dist[v]) {
                    dist[v] = dist[u] + adj[u][v];
                    prev[v] = u;
                }
            }
        }
    }

    if (dist[dst] == INF) {
        printf("[]\n");
    } else {
        int path[MAX_NODES];
        int count = 0;
        int curr = dst;
        while(curr != -1) {
            path[count++] = curr;
            curr = prev[curr];
        }
        printf("[");
        for(int i=count-1; i>=0; i--) {
            printf("%d%s", path[i], i==0 ? "" : ", ");
        }
        printf("]\n");
    }
    return 0;
}
EOF
    gcc -o /app/oracle_path_finder /app/oracle.c -lsqlite3
    strip /app/oracle_path_finder

    # Create buggy C program
    cat << 'EOF' > /home/user/path_finder.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    sqlite3 *db;
    sqlite3_open("/app/lineage.db", &db);
    char query[1024];
    sprintf(query, "WITH RECURSIVE paths AS (SELECT source, target, weight FROM edges WHERE source = %s UNION ALL SELECT p.source, e.target, p.weight + e.weight FROM paths p, edges e) SELECT * FROM paths;", argv[1]);

    // TODO: execute query and print path
    printf("[]\n");
    return 0;
}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
