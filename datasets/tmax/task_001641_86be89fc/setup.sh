#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential time
    pip3 install pytest

    mkdir -p /app/libmathgraph-1.4.2/src
    mkdir -p /app/test_data

    # Create header file
    cat << 'EOF' > /app/libmathgraph-1.4.2/src/graph_solve.h
#ifndef GRAPH_SOLVE_H
#define GRAPH_SOLVE_H

typedef struct {
    int id;
    int edge_count;
    int* edges;
} Node;

typedef struct {
    int node_count;
    Node* nodes;
} Graph;

Graph* load_graph(const char* filename);
void free_graph(Graph* g);
double solve_graph(Graph* g);

#endif
EOF

    # Create buggy source file
    cat << 'EOF' > /app/libmathgraph-1.4.2/src/graph_solve.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "graph_solve.h"

Graph* load_graph(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) return NULL;

    Graph* g = malloc(sizeof(Graph));
    if (fscanf(f, "%d", &g->node_count) != 1) {
        free(g);
        return NULL;
    }
    g->nodes = malloc(sizeof(Node) * g->node_count);

    for (int i = 0; i < g->node_count; i++) {
        g->nodes[i].id = i;
        if (fscanf(f, "%d", &g->nodes[i].edge_count) != 1) break;
        g->nodes[i].edges = malloc(sizeof(int) * g->nodes[i].edge_count);
        for (int j = 0; j < g->nodes[i].edge_count; j++) {
            if (fscanf(f, "%d", &g->nodes[i].edges[j]) != 1) break;
        }
    }
    fclose(f);
    return g;
}

void free_graph(Graph* g) {
    if (!g) return;
    for (int i = 0; i < g->node_count; i++) {
        free(g->nodes[i].edges);
    }
    free(g->nodes);
    free(g);
}

double solve_graph(Graph* g) {
    double total = 0.0;
    for (int i = 0; i < g->node_count; i++) {
        Node* node = &g->nodes[i];
        // Off-by-one bug here
        for (int j = 0; j <= node->edge_count; j++) {
            total += sin((double)node->edges[j]);
        }
    }
    return total;
}
EOF

    # Create main file
    cat << 'EOF' > /app/libmathgraph-1.4.2/src/main.c
#include <stdio.h>
#include "graph_solve.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <graph_file>\n", argv[0]);
        return 1;
    }
    Graph* g = load_graph(argv[1]);
    if (g) {
        printf("Result: %f\n", solve_graph(g));
        free_graph(g);
    } else {
        fprintf(stderr, "Failed to load graph\n");
        return 1;
    }
    return 0;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/libmathgraph-1.4.2/Makefile
CC = gcc
CFLAGS = -Wall -g

all: mathgraph_solver

mathgraph_solver: src/graph_solve.c src/main.c
	$(CC) $(CFLAGS) -o mathgraph_solver src/graph_solve.c src/main.c

clean:
	rm -f mathgraph_solver mathgraph_cli
EOF

    # Generate large graph test data
    cat << 'EOF' > /app/generate_graph.py
import random
random.seed(42)
node_count = 100000
with open('/app/test_data/large_graph.mtx', 'w') as f:
    f.write(f"{node_count}\n")
    for i in range(node_count):
        edge_count = random.randint(10, 50)
        f.write(f"{edge_count} ")
        edges = [random.randint(0, node_count-1) for _ in range(edge_count)]
        f.write(" ".join(map(str, edges)) + "\n")
EOF

    python3 /app/generate_graph.py
    rm /app/generate_graph.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
