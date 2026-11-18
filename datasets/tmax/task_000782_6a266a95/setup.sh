#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/cgraph-1.0
    cat << 'EOF' > /app/cgraph-1.0/cgraph.h
#ifndef CGRAPH_H
#define CGRAPH_H
typedef struct Graph Graph;
Graph* create_graph(int num_nodes);
void add_edge(Graph* g, int from, int to);
int has_cycle(Graph* g);
#endif
EOF

    cat << 'EOF' > /app/cgraph-1.0/cgraph.c
#include "cgraph.h"
#include <stdlib.h>
struct Graph { int nodes; int** adj; };
Graph* create_graph(int num_nodes) {
    Graph* g = malloc(sizeof(Graph));
    g->nodes = num_nodes;
    g->adj = calloc(num_nodes, sizeof(int*));
    for(int i=0; i<num_nodes; i++) g->adj[i] = calloc(num_nodes, sizeof(int));
    return g;
}
void add_edge(Graph* g, int from, int to) {
    if(from < g->nodes && to < g->nodes) g->adj[from][to] = 1;
}
int has_cycle_util(Graph* g, int v, int* visited, int* recStack) {
    if(!visited[v]) {
        visited[v] = 1; recStack[v] = 1;
        for(int i=0; i<g->nodes; i++) {
            if(g->adj[v][i]) {
                if(!visited[i] && has_cycle_util(g, i, visited, recStack)) return 1;
                else if(recStack[i]) return 1;
            }
        }
    }
    recStack[v] = 0; return 0;
}
int has_cycle(Graph* g) {
    int* visited = calloc(g->nodes, sizeof(int));
    int* recStack = calloc(g->nodes, sizeof(int));
    for(int i=0; i<g->nodes; i++) {
        if(has_cycle_util(g, i, visited, recStack)) {
            free(visited); free(recStack); return 1;
        }
    }
    free(visited); free(recStack); return 0;
}
EOF

    cat << 'EOF' > /app/cgraph-1.0/Makefile
all: libcgraph.a
libcgraph.a: cgraph.o
	ar rcs libcgraph.a cgraph.o
cgraph.o: cgraph.c
	gcc -c cgraph.c -o cgrapk.o 
# PERTURBATION: 'cgrapk.o' typo prevents linking. Agent must fix to 'cgraph.o'.
clean:
	rm -f *.o *.a
EOF

    mkdir -p /app/corpora/evil /app/corpora/clean

    # Clean 1: Sequential access
    cat << 'EOF' > /app/corpora/clean/1.txt
T1 READ A
T1 WRITE A
T2 READ B
T2 WRITE B
EOF

    # Clean 2: Safe wait (T2 waits for T1, no cycle)
    cat << 'EOF' > /app/corpora/clean/2.txt
T1 READ A
T2 WRITE A
T1 READ B
EOF

    # Evil 1: Classic Deadlock
    cat << 'EOF' > /app/corpora/evil/1.txt
T1 READ A
T2 READ B
T1 WRITE B
T2 WRITE A
EOF

    # Evil 2: 3-way Deadlock
    cat << 'EOF' > /app/corpora/evil/2.txt
T1 WRITE A
T2 WRITE B
T3 WRITE C
T1 READ B
T2 READ C
T3 READ A
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
