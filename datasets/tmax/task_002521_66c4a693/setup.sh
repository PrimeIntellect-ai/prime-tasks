#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ binutils
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/data_catalog.db')
c = conn.cursor()
c.execute('CREATE TABLE tables (table_id INTEGER PRIMARY KEY, table_name TEXT)')
c.execute('CREATE TABLE foreign_keys (fk_id INTEGER PRIMARY KEY, from_table_id INTEGER, to_table_id INTEGER)')

for i in range(1, 101):
    c.execute('INSERT INTO tables (table_id, table_name) VALUES (?, ?)', (i, f'table_{i}'))

edges = set()
for i in range(2, 101):
    u = random.randint(1, i - 1)
    v = i
    edges.add((u, v))

while len(edges) < 150:
    u = random.randint(1, 100)
    v = random.randint(1, 100)
    if u != v:
        edges.add((min(u, v), max(u, v)))

for i, (u, v) in enumerate(edges):
    c.execute('INSERT INTO foreign_keys (fk_id, from_table_id, to_table_id) VALUES (?, ?, ?)', (i+1, u, v))

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    cat << 'EOF' > /tmp/legacy.cpp
#include <iostream>
#include <sqlite3.h>
#include <vector>
#include <queue>
#include <map>
#include <set>
#include <cstdlib>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    int src = atoi(argv[1]);
    int dst = atoi(argv[2]);

    if (src == dst) {
        cout << 0 << endl;
        return 0;
    }

    sqlite3* db;
    if (sqlite3_open("/home/user/data_catalog.db", &db)) return 1;

    map<int, set<int>> adj;
    map<int, int> degree;

    const char* sql = "SELECT from_table_id, to_table_id FROM foreign_keys";
    sqlite3_stmt* stmt;
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int u = sqlite3_column_int(stmt, 0);
        int v = sqlite3_column_int(stmt, 1);
        adj[u].insert(v);
        adj[v].insert(u);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    for (auto const& pair : adj) {
        degree[pair.first] = pair.second.size();
    }

    map<int, int> dist;
    for (int i = 1; i <= 100; ++i) dist[i] = 1e9;
    dist[src] = 0;

    priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;
    pq.push({0, src});

    while (!pq.empty()) {
        pair<int, int> top = pq.top();
        int d = top.first;
        int u = top.second;
        pq.pop();

        if (d > dist[u]) continue;
        if (u == dst) break;

        for (int v : adj[u]) {
            int weight = degree[u] + degree[v];
            if (dist[u] + weight < dist[v]) {
                dist[v] = dist[u] + weight;
                pq.push({dist[v], v});
            }
        }
    }

    if (dist[dst] == 1e9) cout << -1 << endl;
    else cout << dist[dst] << endl;

    return 0;
}
EOF

    g++ -O3 /tmp/legacy.cpp -o /app/legacy_join_cost_engine -lsqlite3
    strip /app/legacy_join_cost_engine

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
