#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc build-essential libxml2-dev wget tar
    pip3 install pytest

    # Download and extract igraph-0.10.4
    mkdir -p /app
    cd /app
    wget https://github.com/igraph/igraph/releases/download/0.10.4/igraph-0.10.4.tar.gz
    tar -xzf igraph-0.10.4.tar.gz
    rm igraph-0.10.4.tar.gz

    # Inject the simulated corruption
    sed -i '42i #error "Simulated corruption in igraph"' /app/igraph-0.10.4/src/paths/unweighted.c

    # Create and compile the oracle program
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.c
#include <stdio.h>
#include <stdlib.h>

typedef struct Node {
    int dest;
    struct Node* next;
} Node;

typedef struct {
    Node* head;
} AdjList;

typedef struct {
    int V;
    AdjList* array;
} Graph;

Graph* createGraph(int V) {
    Graph* graph = (Graph*)malloc(sizeof(Graph));
    graph->V = V;
    graph->array = (AdjList*)malloc(V * sizeof(AdjList));
    for (int i = 0; i < V; ++i)
        graph->array[i].head = NULL;
    return graph;
}

void addEdge(Graph* graph, int src, int dest) {
    Node* newNode = (Node*)malloc(sizeof(Node));
    newNode->dest = dest;
    newNode->next = graph->array[src].head;
    graph->array[src].head = newNode;
}

int shortestPath(Graph* graph, int start, int end) {
    if (start == end) return 0;
    int V = graph->V;
    int* dist = (int*)malloc(V * sizeof(int));
    for (int i = 0; i < V; i++) dist[i] = -1;

    int* queue = (int*)malloc(V * sizeof(int));
    int front = 0, rear = 0;

    dist[start] = 0;
    queue[rear++] = start;

    while (front < rear) {
        int u = queue[front++];
        Node* temp = graph->array[u].head;
        while (temp) {
            int v = temp->dest;
            if (dist[v] == -1) {
                dist[v] = dist[u] + 1;
                if (v == end) {
                    int res = dist[v];
                    free(dist);
                    free(queue);
                    return res;
                }
                queue[rear++] = v;
            }
            temp = temp->next;
        }
    }
    free(dist);
    free(queue);
    return -1;
}

int main() {
    int V, E;
    if (scanf("%d %d", &V, &E) != 2) return 0;
    Graph* graph = createGraph(V);
    for (int i = 0; i < E; i++) {
        int u, v;
        if (scanf("%d %d", &u, &v) == 2) {
            addEdge(graph, u, v);
        }
    }
    int Q;
    if (scanf("%d", &Q) != 1) return 0;
    for (int i = 0; i < Q; i++) {
        int start, end;
        if (scanf("%d %d", &start, &end) == 2) {
            printf("%d\n", shortestPath(graph, start, end));
        }
    }
    return 0;
}
EOF

    gcc -O3 /opt/oracle/oracle.c -o /opt/oracle/graph_validator_oracle
    chmod +x /opt/oracle/graph_validator_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
