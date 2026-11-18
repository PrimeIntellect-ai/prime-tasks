#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/samples/evil
    mkdir -p /home/user/samples/clean
    mkdir -p /hidden/corpus/evil
    mkdir -p /hidden/corpus/clean

    # Create the query analyzer source code
    cat << 'EOF' > /app/query_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <query.json>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        printf("Error opening file\n");
        return 1;
    }
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, f);
    buffer[len] = '\0';
    fclose(f);

    if (strstr(buffer, "\"depth\": \"*\"") != NULL || strstr(buffer, "\"WHERE\": \"\"") != NULL || strstr(buffer, "[*]") != NULL) {
        printf("PLAN: FULL_SCAN\n");
    } else if (strstr(buffer, "\"type\": \"graph\"") != NULL && strstr(buffer, "\"centrality\": true") != NULL) {
        printf("CENTRALITY > 100\n");
    } else {
        printf("PLAN: INDEX_SCAN\n");
    }
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -o /app/query_analyzer /app/query_analyzer.c
    strip /app/query_analyzer
    rm /app/query_analyzer.c

    # Create sample corpora
    cat << 'EOF' > /home/user/samples/evil/evil1.json
{
    "type": "graph",
    "query": "MATCH (n)-[*]->(m) RETURN n",
    "depth": "*"
}
EOF

    cat << 'EOF' > /home/user/samples/evil/evil2.json
{
    "type": "graph",
    "query": "CALL algo.betweenness.stream('User') YIELD nodeId, score",
    "centrality": true
}
EOF

    cat << 'EOF' > /home/user/samples/clean/clean1.json
{
    "type": "relational",
    "query": "SELECT * FROM users WHERE id = 5",
    "WHERE": "id = 5"
}
EOF

    # Create hidden corpora
    cat << 'EOF' > /hidden/corpus/evil/evil_hidden1.json
{
    "type": "relational",
    "query": "SELECT * FROM users",
    "WHERE": ""
}
EOF

    cat << 'EOF' > /hidden/corpus/evil/evil_hidden2.json
{
    "type": "graph",
    "query": "MATCH (n)-[*]->(m) RETURN m",
    "depth": "*"
}
EOF

    cat << 'EOF' > /hidden/corpus/clean/clean_hidden1.json
{
    "type": "graph",
    "query": "MATCH (n:User {id: 123})-[:KNOWS]->(m) RETURN m",
    "depth": "1"
}
EOF

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
