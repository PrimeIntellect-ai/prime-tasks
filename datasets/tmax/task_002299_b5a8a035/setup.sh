#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/db_graph.txt
DB_WEB DB_USERS
DB_USERS DB_AUTH
DB_WEB DB_PRODUCTS
DB_PRODUCTS DB_INVENTORY
DB_INVENTORY DB_AUTH
DB_PRODUCTS DB_LOGS
DB_LOGS DB_AUTH
EOF

    cat << 'EOF' > /home/user/backup_planner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 100
#define MAX_NAME 50

typedef struct {
    char name[MAX_NAME];
} Node;

typedef struct {
    int from;
    int to;
} Edge;

Node nodes[MAX_NODES];
int node_count = 0;

Edge edges[MAX_NODES * MAX_NODES];
int edge_count = 0;

int get_or_add_node(const char* name) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i].name, name) == 0) return i;
    }
    strcpy(nodes[node_count].name, name);
    return node_count++;
}

void load_graph(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) return;
    char from[MAX_NAME], to[MAX_NAME];
    while (fscanf(f, "%s %s", from, to) == 2) {
        int u = get_or_add_node(from);
        int v = get_or_add_node(to);
        edges[edge_count].from = u;
        edges[edge_count].to = v;
        edge_count++;
    }
    fclose(f);
}

// BUG: Missing visited array, causes explosion/loops
void traverse(int u) {
    printf("%s\n", nodes[u].name);
    for (int i = 0; i < edge_count; i++) {
        if (edges[i].from == u) {
            traverse(edges[i].to);
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    load_graph("/home/user/db_graph.txt");

    int start_idx = -1;
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i].name, argv[1]) == 0) {
            start_idx = i;
            break;
        }
    }

    if (start_idx != -1) {
        traverse(start_idx);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
