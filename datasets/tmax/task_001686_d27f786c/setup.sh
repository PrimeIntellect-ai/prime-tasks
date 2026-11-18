#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ sqlite3 libsqlite3-dev
    pip3 install pytest pandas numpy

    mkdir -p /app

    cat << 'EOF' > /app/legacy_etl.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if(argc != 3) {
        printf("Usage: %s <db_path> <num_edges>\n", argv[0]);
        return 1;
    }
    char cmd[2048];
    sprintf(cmd, "python3 -c \"\n\
import sqlite3, sys, random\n\
conn = sqlite3.connect('%s')\n\
conn.execute('CREATE TABLE edges(src INTEGER, dst INTEGER)')\n\
random.seed(42)\n\
edges = set()\n\
for _ in range(int('%s')):\n\
    src = random.randint(0, 100)\n\
    dst = random.randint(0, 100)\n\
    edges.add((src, dst))\n\
conn.executemany('INSERT INTO edges VALUES (?, ?)', list(edges))\n\
conn.execute('CREATE INDEX idx_src ON edges(src)')\n\
conn.commit()\n\
conn.close()\n\
\"", argv[1], argv[2]);
    system(cmd);
    return 0;
}
EOF

    gcc -O2 -s /app/legacy_etl.c -o /app/legacy_etl
    rm /app/legacy_etl.c

    cat << 'EOF' > /verify.py
import sqlite3
import pandas as pd
import numpy as np
import sys
import os

def verify():
    if not os.path.exists('/home/user/pagerank_results.csv'):
        print("CSV not found")
        sys.exit(1)

    conn = sqlite3.connect('/home/user/graph.db')
    conn.execute("REINDEX;")

    query = """
    WITH RECURSIVE reachable(node) AS (
        SELECT 0
        UNION
        SELECT e.dst FROM edges e
        JOIN reachable r ON e.src = r.node
    )
    SELECT src, dst FROM edges WHERE src IN reachable AND dst IN reachable;
    """
    edges = pd.read_sql_query(query, conn)

    nodes = set(edges['src']).union(set(edges['dst'])).union({0})
    N = len(nodes)

    pr = {n: 1.0 / N for n in nodes}
    out_degree = edges.groupby('src').size().to_dict()

    for _ in range(25):
        new_pr = {n: (1.0 - 0.85) / N for n in nodes}
        for _, row in edges.iterrows():
            u, v = row['src'], row['dst']
            new_pr[v] += 0.85 * (pr[u] / out_degree[u])
        pr = new_pr

    agent_df = pd.read_csv('/home/user/pagerank_results.csv')
    agent_pr = dict(zip(agent_df['node'], agent_df['pagerank']))

    mse = 0.0
    for n in nodes:
        expected = pr[n]
        actual = agent_pr.get(n, 0.0)
        mse += (expected - actual) ** 2
    mse /= N

    print(f"MSE: {mse}")
    if mse <= 1e-8:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    verify()
EOF
    chmod +x /verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
