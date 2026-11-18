#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/deps.txt
module_a: module_b module_c
module_b: module_d
module_c: module_d
module_d: module_e
module_e:
module_f: module_a
EOF

    cat << 'EOF' > /home/user/workspace/graph.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Node {
    char* name;
    int in_degree;
    struct Node* edges[20];
    int edge_count;
} Node;

Node nodes[100];
int node_count = 0;

Node* get_or_create_node(const char* name) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i].name, name) == 0) return &nodes[i];
    }
    // Bug 1: Missing +1 for null terminator causing heap corruption
    nodes[node_count].name = malloc(strlen(name));
    strcpy(nodes[node_count].name, name);
    nodes[node_count].in_degree = 0;
    nodes[node_count].edge_count = 0;
    return &nodes[node_count++];
}

char** get_build_order(const char* filepath, int* out_count) {
    FILE* f = fopen(filepath, "r");
    if (!f) return NULL;

    char line[256];
    node_count = 0;

    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        char* colon = strchr(line, ':');
        if (!colon) continue;
        *colon = '\0';

        Node* target = get_or_create_node(line);
        char* deps = colon + 1;
        char* token = strtok(deps, " ");
        while (token) {
            Node* dep = get_or_create_node(token);
            dep->edges[dep->edge_count++] = target;
            target->in_degree++;
            token = strtok(NULL, " ");
        }
    }
    fclose(f);

    // Topological Sort (Kahn's Algorithm)
    // Bug 2: Returning stack-allocated memory. Should be malloc'd.
    char* result[100];
    int res_count = 0;

    Node* queue[100];
    int head = 0, tail = 0;

    for (int i = 0; i < node_count; i++) {
        if (nodes[i].in_degree == 0) {
            queue[tail++] = &nodes[i];
        }
    }

    while (head < tail) {
        Node* curr = queue[head++];
        result[res_count] = malloc(strlen(curr->name) + 1);
        strcpy(result[res_count], curr->name);
        res_count++;

        for (int i = 0; i < curr->edge_count; i++) {
            curr->edges[i]->in_degree--;
            if (curr->edges[i]->in_degree == 0) {
                queue[tail++] = curr->edges[i];
            }
        }
    }

    *out_count = res_count;
    // Returning local array `result` leads to undefined behavior!
    return result;
}

void free_build_order(char** order, int count) {
    if (!order) return;
    for (int i = 0; i < count; i++) {
        free(order[i]);
    }
    free(order);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
