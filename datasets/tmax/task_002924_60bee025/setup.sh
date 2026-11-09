#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/edges.txt
A B 4
A C 2
B C 5
B D 10
C D 3
D E 11
E A 8
EOF

    cat << 'EOF' > /home/user/graph_etl.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define MAX_NODES 100
#define INF 999999

int adj[MAX_NODES][MAX_NODES];
char nodes[MAX_NODES][20];
int node_count = 0;

int get_node_index(const char* name) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i], name) == 0) return i;
    }
    strcpy(nodes[node_count], name);
    return node_count++;
}

void load_edges(const char* filename) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        perror("Failed to open file");
        exit(1);
    }

    for (int i = 0; i < MAX_NODES; i++) {
        for (int j = 0; j < MAX_NODES; j++) {
            adj[i][j] = (i == j) ? 0 : INF;
        }
    }

    char u_name[20], v_name[20];
    int weight;
    while (fscanf(file, "%s %s %d", u_name, v_name, &weight) == 3) {
        int u = get_node_index(u_name);
        int v_actual = get_node_index(v_name);

        // BUG: Implicit cross join logic
        for (int v = 0; v < node_count; v++) {
            // It assigns the edge to all currently known nodes instead of just v_actual
            adj[u][v] = weight;
        }
        /* Correct logic should be:
        adj[u][v_actual] = weight;
        */
    }
    fclose(file);
}

void dijkstra(int start_node) {
    int dist[MAX_NODES];
    int visited[MAX_NODES];

    for (int i = 0; i < node_count; i++) {
        dist[i] = INF;
        visited[i] = 0;
    }

    dist[start_node] = 0;

    for (int count = 0; count < node_count - 1; count++) {
        int min = INF, u = -1;
        for (int v = 0; v < node_count; v++) {
            if (!visited[v] && dist[v] <= min) {
                min = dist[v];
                u = v;
            }
        }

        if (u == -1) break;
        visited[u] = 1;

        for (int v = 0; v < node_count; v++) {
            if (!visited[v] && adj[u][v] != INF && dist[u] != INF && dist[u] + adj[u][v] < dist[v]) {
                dist[v] = dist[u] + adj[u][v];
            }
        }
    }

    for (int i = 0; i < node_count; i++) {
        if (dist[i] != INF) {
            printf("%s\t%d\n", nodes[i], dist[i]);
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Usage: %s <edges_file> <start_node>\n", argv[0]);
        return 1;
    }

    load_edges(argv[1]);
    int start_idx = -1;
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i], argv[2]) == 0) {
            start_idx = i;
            break;
        }
    }

    if (start_idx == -1) {
        printf("Start node not found.\n");
        return 1;
    }

    dijkstra(start_idx);
    return 0;
}
EOF

    chmod -R 777 /home/user
