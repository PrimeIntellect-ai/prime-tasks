#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 binutils
    pip3 install pytest

    mkdir -p /app

    # Generate the access_graph.tsv
    python3 -c '
import random
nodes = [f"E{i:02d}" for i in range(1, 51)] + \
        [f"G{i:02d}" for i in range(1, 21)] + \
        [f"T{i:02d}" for i in range(1, 51)]
edges = set()
while len(edges) < 200:
    src = random.choice(nodes)
    dst = random.choice(nodes)
    if src != dst:
        edges.add((src, dst))
with open("/app/access_graph.tsv", "w") as f:
    for src, dst in edges:
        f.write(f"{src}\t{dst}\n")
'

    # Create oracle.c
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_EDGES 1000
char src[MAX_EDGES][50];
char dst[MAX_EDGES][50];
int edge_count = 0;

int dfs(const char* current, const char* target, char visited[][50], int* v_count) {
    if (strcmp(current, target) == 0 && *v_count > 0) return 1;
    for (int i = 0; i < *v_count; i++) {
        if (strcmp(visited[i], current) == 0) return 0;
    }
    strcpy(visited[(*v_count)++], current);

    for (int i = 0; i < edge_count; i++) {
        if (strcmp(src[i], current) == 0) {
            if (dfs(dst[i], target, visited, v_count)) return 1;
        }
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    FILE* f = fopen("/app/access_graph.tsv", "r");
    if (!f) return 1;
    while (fscanf(f, "%49s\t%49s", src[edge_count], dst[edge_count]) == 2) {
        edge_count++;
    }
    fclose(f);

    char visited[MAX_EDGES][50];
    int v_count = 0;
    int found = 0;
    for (int i = 0; i < edge_count; i++) {
        if (strcmp(src[i], argv[1]) == 0) {
            if (dfs(dst[i], argv[2], visited, &v_count)) {
                found = 1;
                break;
            }
        }
    }

    if (found) printf("GRANTED\n");
    else printf("DENIED\n");
    return 0;
}
EOF

    # Compile and strip the oracle
    gcc -O2 /tmp/oracle.c -o /app/access_oracle
    strip /app/access_oracle
    rm /tmp/oracle.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
