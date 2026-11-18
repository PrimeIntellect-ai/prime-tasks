#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/qa_env

    cat << 'EOF' > /home/user/qa_env/eval_graph.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 100
#define INF 999999

int parse_expr(char **p) {
    int val = **p - '0';
    (*p)++;
    while (**p == '+' || **p == '*') {
        char op = **p;
        (*p)++;
        int next_val = **p - '0';
        (*p)++;
        // BUG: Left-to-right evaluation ignoring precedence
        if (op == '+') val = val + next_val;
        else if (op == '*') val = val * next_val;
    }
    return val;
}

// Graph structures and Dijkstra's algorithm
typedef struct {
    char name[32];
} Node;

Node nodes[MAX_NODES];
int node_count = 0;
int adj[MAX_NODES][MAX_NODES];

int get_node(char *name) {
    for (int i = 0; i < node_count; i++) {
        if (strcmp(nodes[i].name, name) == 0) return i;
    }
    strcpy(nodes[node_count].name, name);
    return node_count++;
}

int main() {
    for (int i=0; i<MAX_NODES; i++) {
        for (int j=0; j<MAX_NODES; j++) adj[i][j] = INF;
    }

    char src[32], dst[32], expr[128];
    while (scanf("%s %s %s", src, dst, expr) == 3) {
        int u = get_node(src);
        int v = get_node(dst);
        char *p = expr;
        int weight = parse_expr(&p);
        adj[u][v] = weight;
    }

    int start_idx = get_node("START");
    int end_idx = get_node("END");

    int dist[MAX_NODES];
    int visited[MAX_NODES];
    for(int i=0; i<node_count; i++) { dist[i] = INF; visited[i] = 0; }
    dist[start_idx] = 0;

    for (int count = 0; count < node_count - 1; count++) {
        int min = INF, u = -1;
        for (int v = 0; v < node_count; v++) {
            if (!visited[v] && dist[v] <= min) { min = dist[v]; u = v; }
        }
        if (u == -1) break;
        visited[u] = 1;
        for (int v = 0; v < node_count; v++) {
            if (!visited[v] && adj[u][v] != INF && dist[u] != INF && dist[u] + adj[u][v] < dist[v]) {
                dist[v] = dist[u] + adj[u][v];
            }
        }
    }

    printf("%d\n", dist[end_idx]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/qa_env/prod_graph.txt
START A 1+2*3
START B 4*2+1
A C 2+2*2
B C 1+1*1
C END 3*3+2
A END 5*5+5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
