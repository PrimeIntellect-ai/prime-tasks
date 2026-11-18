#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential binutils ltrace strace
pip3 install pytest

mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/edges.csv
A,B,1.0
B,C,1.5
C,D,0.5
D,E,2.0
A,X,1.0
EOF
chmod 644 /home/user/data/edges.csv

mkdir -p /app
cat << 'EOF' > /tmp/engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    char *env_file = getenv("GRAPH_CSV_PATH");
    if (!env_file) {
        fprintf(stderr, "Error: GRAPH_CSV_PATH not set\n");
        return 1;
    }

    char query[256];
    if (!fgets(query, sizeof(query), stdin)) return 1;

    char node[64];
    int hops;
    // Expected format: MATCH PATH FROM 'A' MAX_HOPS 2
    if (sscanf(query, "MATCH PATH FROM '%[^']' MAX_HOPS %d", node, &hops) == 2) {
        if (strcmp(node, "A") == 0 && hops == 2) {
            printf("B\nC\nD\nX\n");
        } else if (strcmp(node, "B") == 0 && hops == 1) {
            printf("C\n");
        } else {
            printf("UNKNOWN\n");
        }
    } else {
        fprintf(stderr, "Invalid query syntax.\n");
        return 1;
    }
    return 0;
}
EOF
gcc -O3 /tmp/engine.c -o /app/query_engine
strip /app/query_engine
chmod 755 /app/query_engine
rm /tmp/engine.c

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/data
chmod -R 777 /home/user
