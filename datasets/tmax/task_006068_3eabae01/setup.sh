#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/bipartite.txt
1 101
2 101
3 101
1 102
4 102
5 103
6 103
1 103
2 104
4 104
7 105
8 105
EOF

    cat << 'EOF' > /home/user/project_graph.c
#include <stdio.h>
#include <stdlib.h>

#define MAX_EDGES 1000

typedef struct {
    int user;
    int product;
} Edge;

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    Edge edges[MAX_EDGES];
    int num_edges = 0;
    while (fscanf(f, "%d %d", &edges[num_edges].user, &edges[num_edges].product) == 2) {
        num_edges++;
    }
    fclose(f);

    int degrees[100] = {0};
    int connected[100][100] = {0};

    for (int i = 0; i < num_edges; i++) {
        for (int j = 0; j < num_edges; j++) {
            // BUG IS HERE: using = instead of ==
            if (edges[i].product = edges[j].product) {
                int u1 = edges[i].user;
                int u2 = edges[j].user;
                if (u1 != u2 && !connected[u1][u2]) {
                    connected[u1][u2] = 1;
                    degrees[u1]++;
                }
            }
        }
    }

    for (int i = 0; i < 100; i++) {
        if (degrees[i] > 0) {
            printf("%d,%d\n", i, degrees[i]);
        }
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
