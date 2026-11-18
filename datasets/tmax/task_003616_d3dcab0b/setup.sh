#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/graph_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 10000

typedef struct Edge {
    int dst;
    struct Edge* next;
} Edge;

typedef struct {
    char name[64];
    long weight;
    Edge* edges;
    int indegree;
    long dp;
} Node;

Node nodes[MAX_NODES];
int node_count = 0;

int get_node(const char* name) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i].name, name) == 0) return i;
    }
    strcpy(nodes[node_count].name, name);
    nodes[node_count].weight = 0;
    nodes[node_count].edges = NULL;
    nodes[node_count].indegree = 0;
    nodes[node_count].dp = 0;
    return node_count++;
}

void add_edge(int src, int dst) {
    Edge* e = malloc(sizeof(Edge));
    e->dst = dst;
    e->next = nodes[src].edges;
    nodes[src].edges = e;
    nodes[dst].indegree++;
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        if (line[0] == 'N') {
            char name[64];
            long w;
            if (sscanf(line, "N %s %ld", name, &w) == 2) {
                int u = get_node(name);
                nodes[u].weight = w;
            }
        } else if (line[0] == 'E') {
            char src[64], dst[64];
            if (sscanf(line, "E %s %s", src, dst) == 2) {
                int u = get_node(src);
                int v = get_node(dst);
                add_edge(u, v);
            }
        }
    }
    fclose(f);

    int q[MAX_NODES];
    int head = 0, tail = 0;
    for (int i = 0; i < node_count; i++) {
        if (nodes[i].indegree == 0) {
            q[tail++] = i;
            nodes[i].dp = nodes[i].weight;
        }
    }

    long max_path = 0;
    while (head < tail) {
        int u = q[head++];
        if (nodes[u].dp > max_path) max_path = nodes[u].dp;
        for (Edge* e = nodes[u].edges; e; e = e->next) {
            int v = e->dst;
            if (nodes[u].dp + nodes[v].weight > nodes[v].dp) {
                nodes[v].dp = nodes[u].dp + nodes[v].weight;
            }
            if (--nodes[v].indegree == 0) {
                q[tail++] = v;
            }
        }
    }

    printf("MAX_PATH: %ld\n", max_path);
    return 0;
}
EOF

    gcc -O2 /app/graph_oracle.c -o /app/graph_oracle
    strip /app/graph_oracle
    rm /app/graph_oracle.c

    cat << 'EOF' > /app/parser_fix.patch
--- old_parser.c
+++ new_parser.c
@@ -45,6 +45,7 @@
     while (fgets(line, sizeof(line), f)) {
+        if (line[0] == '#') continue;
         if (line[0] == '\n' || line[0] == '\r') continue;
EOF

    cat << 'EOF' > /app/bench.py
#!/usr/bin/env python3
import os
import sys

print("Benchmarking...")
sys.exit(0)
EOF
    chmod +x /app/bench.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
