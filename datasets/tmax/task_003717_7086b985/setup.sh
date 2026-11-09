#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/graph_engine.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, stdin);
    buffer[len] = '\0';
    if (strstr(buffer, "stale_rels") || strstr(buffer, ":CORRUPT")) {
        abort(); // Simulate engine crash on corrupted index
    }
    printf("node_id|label|prop_value\n101|Person|Developer\n102|System|Database\n");
    return 0;
}
EOF

    gcc -o /app/graph_engine /app/graph_engine.c
    strip /app/graph_engine
    rm /app/graph_engine.c

    mkdir -p /home/user/clean
    mkdir -p /home/user/evil

    echo "MATCH (n:Person) RETURN n.id, n.name" > /home/user/clean/q1.txt
    echo "MATCH (a)-[:KNOWS]->(b) USING INDEX fast_rels RETURN a, b" > /home/user/clean/q2.txt

    echo "MATCH (n)-[:CORRUPT]->(m) RETURN m" > /home/user/evil/e1.txt
    echo "MATCH (a)-[r]->(b) USING INDEX stale_rels RETURN r" > /home/user/evil/e2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
