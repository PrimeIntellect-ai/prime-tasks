#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/sys_debug
    cd /home/user/sys_debug

    cat << 'EOF' > matrix.c
#include <stdlib.h>

int** create_matrix(int size) {
    int** mat = (int**)malloc(size * sizeof(int*));
    for(int i=0; i<size; i++) {
        mat[i] = (int*)calloc(size, sizeof(int));
    }
    return mat;
}
EOF

    cat << 'EOF' > graph.c
#include "graph.h"
#include <stdlib.h>

int** adj_matrix;
int graph_size;

// Provided by libmatrix.so
extern int** create_matrix(int size);

void init_graph(int num_nodes) {
    graph_size = num_nodes;
    adj_matrix = create_matrix(num_nodes);
}

void add_edge(int from, int to) {
    if (from < graph_size && to < graph_size) {
        adj_matrix[from][to] = 1;
    }
}

int traverse_and_count(int start_node) {
    int count = 0;
    int* visited = (int*)calloc(graph_size, sizeof(int));
    int* queue = (int*)malloc(graph_size * sizeof(int));
    int head = 0, tail = 0;

    queue[tail++] = start_node;
    visited[start_node] = 1;

    while(head < tail) {
        int curr = queue[head++];
        count++;
        for(int i=0; i<graph_size; i++) {
            if(adj_matrix[curr][i] && !visited[i]) {
                visited[i] = 1;
                queue[tail++] = i;
            }
        }
    }
    free(visited);
    free(queue);
    return count;
}
EOF

    cat << 'EOF' > graph.h
#ifndef GRAPH_H
#define GRAPH_H

void init_graph(int num_nodes);
void add_edge(int from, int to);
int traverse_and_count(int start_node);

#endif
EOF

    cat << 'EOF' > graph_def.txt
NODE 0
DEPENDS 1
DEPENDS 2
END
NODE 1
DEPENDS 3
END
NODE 2
DEPENDS 4
DEPENDS 5
END
NODE 3
END
NODE 4
DEPENDS 6
END
NODE 5
END
NODE 6
END
EOF

    cat << 'EOF' > Makefile
all: libmatrix.so libgraph.so

libmatrix.so: matrix.c
	gcc -shared -fPIC -o libmatrix.so matrix.c

libgraph.so: graph.c
	gcc -shared -fPIC -o libgraph.so graph.c

clean:
	rm -f *.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
