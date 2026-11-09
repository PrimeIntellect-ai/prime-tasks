#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/libgraphdump-1.2.0

    cat << 'EOF' > /app/libgraphdump-1.2.0/graphdump.h
#ifndef GRAPHDUMP_H
#define GRAPHDUMP_H

#include <stdint.h>

typedef struct {
    int32_t u;
    int32_t v;
} Edge;

typedef struct {
    int32_t num_nodes;
    int32_t num_edges;
    Edge* edges;
} Graph;

// Returns 0 on success, -1 on failure
int parse_graph_dump(const char* filename, Graph* g);
void free_graph(Graph* g);

#endif
EOF

    cat << 'EOF' > /app/libgraphdump-1.2.0/graphdump.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graphdump.h"

int parse_graph_dump(const char* filename, Graph* g) {
    FILE* f = fopen(filename, "rb");
    if (!f) return -1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "GDB1", 4) != 0) {
        fclose(f);
        return -1;
    }

    if (fread(&g->num_nodes, 4, 1, f) != 1) { fclose(f); return -1; }
    if (fread(&g->num_edges, 4, 1, f) != 1) { fclose(f); return -1; }

    g->edges = malloc(sizeof(Edge) * g->num_edges);
    if (fread(g->edges, sizeof(Edge), g->num_edges, f) != (size_t)g->num_edges) {
        free(g->edges);
        fclose(f);
        return -1;
    }

    fclose(f);
    return 0;
}

void free_graph(Graph* g) {
    if (g->edges) free(g->edges);
}
EOF

    cat << 'EOF' > /app/libgraphdump-1.2.0/Makefile
libgraphdump.so: graphdump.o
	gcc -shared -o libgraphdump.so graphdump.o

graphdump.o: graphdump.c
	gcc -c graphdump.c -Wall

clean:
	rm -f *.o *.so
EOF

    useradd -m -s /bin/bash user || true

    python3 -c '
import struct
with open("/home/user/backup.dat", "wb") as f:
    f.write(b"GDB1")
    f.write(struct.pack("<ii", 6, 5))
    edges = [(0,1), (1,2), (2,3), (3,4), (4,5)]
    for u, v in edges:
        f.write(struct.pack("<ii", u, v))
'

    chmod -R 777 /app
    chmod -R 777 /home/user
