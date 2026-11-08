#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /test
    mkdir -p /app

    cat << 'EOF' > /tmp/gen_data.py
import random
import json

def gen_data(num_nodes, num_edges, num_queries, edges_file, queries_file):
    random.seed(42)
    with open(edges_file, 'w') as f:
        for _ in range(num_edges):
            u = random.randint(0, num_nodes - 1)
            v = random.randint(0, num_nodes - 1)
            w = round(random.uniform(1.0, 10.0), 2)
            p = round(random.uniform(0.5, 2.0), 2)
            props = json.dumps({"type": "friend", "penalty": p})
            f.write(f"{u},{v},{w},{props}\n")

    with open(queries_file, 'w') as f:
        for _ in range(num_queries):
            u = random.randint(0, num_nodes - 1)
            v = random.randint(0, num_nodes - 1)
            f.write(f"{u} {v}\n")

gen_data(10000, 50000, 100, '/home/user/data/edges.csv', '/home/user/data/queries.txt')
gen_data(20000, 200000, 500, '/test/edges_test.csv', '/test/queries_test.txt')
EOF

    python3 /tmp/gen_data.py

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 30000
#define INF 1e9

typedef struct Edge {
    int target;
    double weight;
    struct Edge* next;
} Edge;

void free_graph(Edge** graph, int num_nodes) {
    for (int i = 0; i < num_nodes; i++) {
        Edge* curr = graph[i];
        while (curr) {
            Edge* temp = curr;
            curr = curr->next;
            free(temp);
        }
        graph[i] = NULL;
    }
}

double solve_query(const char* csv_path, int src, int dst) {
    FILE* f = fopen(csv_path, "r");
    if (!f) return -1.0;

    Edge** graph = calloc(MAX_NODES, sizeof(Edge*));
    char line[1024];
    int max_node = 0;
    while (fgets(line, sizeof(line), f)) {
        int u, v;
        double base_weight;
        char props[512];
        if (sscanf(line, "%d,%d,%lf,%[^\n]", &u, &v, &base_weight, props) == 4) {
            double penalty = 1.0;
            char* p = strstr(props, "\"penalty\":");
            if (p) {
                sscanf(p + 10, "%lf", &penalty);
            }
            double w = base_weight * penalty;
            Edge* e = malloc(sizeof(Edge));
            e->target = v;
            e->weight = w;
            e->next = graph[u];
            graph[u] = e;
            if (u > max_node) max_node = u;
            if (v > max_node) max_node = v;
        }
    }
    fclose(f);

    if (src >= MAX_NODES || dst >= MAX_NODES || src > max_node || dst > max_node) {
        free_graph(graph, MAX_NODES);
        return -1.0;
    }

    double* dist = malloc(MAX_NODES * sizeof(double));
    int* visited = calloc(MAX_NODES, sizeof(int));
    for (int i = 0; i < MAX_NODES; i++) dist[i] = INF;
    dist[src] = 0.0;

    for (int i = 0; i <= max_node; i++) {
        int u = -1;
        double min_d = INF;
        for (int j = 0; j <= max_node; j++) {
            if (!visited[j] && dist[j] < min_d) {
                min_d = dist[j];
                u = j;
            }
        }
        if (u == -1 || u == dst) break;
        visited[u] = 1;

        for (Edge* e = graph[u]; e; e = e->next) {
            if (dist[u] + e->weight < dist[e->target]) {
                dist[e->target] = dist[u] + e->weight;
            }
        }
    }

    double ans = dist[dst] == INF ? -1.0 : dist[dst];
    free_graph(graph, MAX_NODES);
    free(dist);
    free(visited);
    return ans;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    FILE* qf = fopen(argv[2], "r");
    if (!qf) return 1;
    int u, v;
    while (fscanf(qf, "%d %d", &u, &v) == 2) {
        double d = solve_query(argv[1], u, v);
        printf("%.2f\n", d);
    }
    fclose(qf);
    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/graph_oracle
    strip /app/graph_oracle

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /test
