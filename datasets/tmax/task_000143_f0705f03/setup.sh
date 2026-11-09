#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean
    sqlite3 /app/graph.db "CREATE TABLE edges (src INTEGER, dst INTEGER, weight INTEGER, type TEXT);"
    sqlite3 /app/graph.db "CREATE INDEX idx_stale_edges ON edges(src, type);"
    sqlite3 /app/graph.db "CREATE INDEX idx_safe_edges ON edges(src, dst);"

    cat << 'EOF' > /tmp/compiler.c
#include <stdio.h>
#include <string.h>
int main() {
    char buf[256];
    if (fgets(buf, sizeof(buf), stdin)) {
        if (strstr(buf, ":Type")) {
            printf("WITH RECURSIVE traverse(node) AS (SELECT dst FROM edges WHERE src=1 AND type='Type' UNION ALL SELECT dst FROM edges JOIN traverse ON edges.src = traverse.node) SELECT * FROM traverse;\n");
        } else {
            printf("WITH RECURSIVE traverse(node) AS (SELECT dst FROM edges WHERE src=1 AND dst=2 UNION ALL SELECT dst FROM edges JOIN traverse ON edges.src = traverse.node) SELECT * FROM traverse;\n");
        }
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/compiler.c -o /app/graph_compiler
    chmod +x /app/graph_compiler

    echo "MATCH (a:Type {id: 1})-[r]->(b)" > /app/corpus/evil/1.gql
    echo "MATCH (a:Type {id: 42})-[r]->(b)" > /app/corpus/evil/2.gql
    echo "MATCH (a {id: 1})-[r]->(b {id: 2})" > /app/corpus/clean/1.gql
    echo "MATCH (a {id: 5})-[r]->(b {id: 9})" > /app/corpus/clean/2.gql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
