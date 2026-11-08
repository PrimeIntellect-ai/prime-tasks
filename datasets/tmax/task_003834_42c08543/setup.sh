#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc make
    pip3 install pytest

    # Create directories
    mkdir -p /app/libgraphcsv-1.2.0
    mkdir -p /opt/oracle

    # Create libgraphcsv files
    cat << 'EOF' > /app/libgraphcsv-1.2.0/graphcsv.h
#ifndef GRAPHCSV_H
#define GRAPHCSV_H

#ifndef MAX_RECURSION_DEPTH
#define MAX_RECURSION_DEPTH 100
#endif

typedef struct Edge {
    char source[64];
    char target[64];
    char target_type[64];
    int weight;
    struct Edge* next;
} Edge;

typedef struct Graph {
    Edge* head;
} Graph;

Graph* parse_csv(const char* filename);
void free_graph(Graph* g);
Edge* get_edges_by_source(Graph* g, const char* source);

#endif
EOF

    cat << 'EOF' > /app/libgraphcsv-1.2.0/graphcsv.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graphcsv.h"

Graph* parse_csv(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) return NULL;
    Graph* g = (Graph*)malloc(sizeof(Graph));
    g->head = NULL;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        Edge* e = (Edge*)malloc(sizeof(Edge));
        sscanf(line, "%[^,],%[^,],%[^,],%d", e->source, e->target, e->target_type, &e->weight);
        e->next = g->head;
        g->head = e;
    }
    fclose(f);
    return g;
}

void free_graph(Graph* g) {
    if (!g) return;
    Edge* curr = g->head;
    while (curr) {
        Edge* next = curr->next;
        free(curr);
        curr = next;
    }
    free(g);
}

Edge* get_edges_by_source(Graph* g, const char* source) {
    Edge* result = NULL;
    Edge* curr = g->head;
    while (curr) {
        if (strcmp(curr->source, source) == 0) {
            Edge* copy = (Edge*)malloc(sizeof(Edge));
            *copy = *curr;
            copy->next = result;
            result = copy;
        }
        curr = curr->next;
    }
    return result;
}
EOF

    cat << 'EOF' > /app/libgraphcsv-1.2.0/Makefile
CC=gcc
CFLAGS=-O2 -Wall -DMAX_RECURSION_DEPTH=3 -fPIC
LDFLAGS=-shared

all: libgraphcsv.so

libgraphcsv.so: graphcsv.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o libgraphcsv.so graphcsv.c

install: libgraphcsv.so
	cp libgraphcsv.so /usr/local/lib/
	cp graphcsv.h /usr/local/include/
	ldconfig

clean:
	rm -f libgraphcsv.so
EOF

    # Create oracle program
    cat << 'EOF' > /opt/oracle/exposure_calculator_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 10000

typedef struct Edge {
    char source[64];
    char target[64];
    char target_type[64];
    int weight;
    struct Edge* next;
} Edge;

Edge* graph = NULL;

void add_edge(const char* s, const char* t, const char* tt, int w) {
    Edge* e = malloc(sizeof(Edge));
    strcpy(e->source, s);
    strcpy(e->target, t);
    strcpy(e->target_type, tt);
    e->weight = w;
    e->next = graph;
    graph = e;
}

int visited(const char** path, int depth, const char* node) {
    for (int i = 0; i < depth; i++) {
        if (strcmp(path[i], node) == 0) return 1;
    }
    return 0;
}

int dfs(const char* current, const char** path, int depth, int expected_type) {
    int total = 0;
    path[depth] = current;

    Edge* curr = graph;
    while (curr) {
        if (strcmp(curr->source, current) == 0) {
            int is_valid_type = 0;
            if (expected_type == 0 && strcmp(curr->target_type, "ACCOUNT") == 0) is_valid_type = 1;
            if (expected_type == 1 && strcmp(curr->target_type, "COMPANY") == 0) is_valid_type = 1;

            if (is_valid_type && !visited(path, depth + 1, curr->target)) {
                total += curr->weight;
                total += dfs(curr->target, path, depth + 1, 1 - expected_type);
            }
        }
        curr = curr->next;
    }
    return total;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char s[64], t[64], tt[64];
        int w;
        if (sscanf(line, "%[^,],%[^,],%[^,],%d", s, t, tt, &w) == 4) {
            add_edge(s, t, tt, w);
        }
    }
    fclose(f);

    const char* path[1000];
    int total = dfs(argv[2], path, 0, 0);
    printf("%d\n", total);
    return 0;
}
EOF

    gcc -O2 -o /opt/oracle/exposure_calculator_oracle /opt/oracle/exposure_calculator_oracle.c
    chmod +x /opt/oracle/exposure_calculator_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
