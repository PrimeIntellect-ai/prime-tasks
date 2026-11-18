#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zbar-tools gcc
pip3 install pytest qrcode Pillow opencv-python-headless numpy

mkdir -p /app

cat << 'EOF' > /app/generate_video.py
import qrcode
import cv2
import numpy as np
import random
import os

os.makedirs('/app', exist_ok=True)

# Generate a random graph
random.seed(42)
num_nodes = 50
edges = []
for _ in range(150):
    u = random.randint(0, num_nodes - 1)
    v = random.randint(0, num_nodes - 1)
    w = random.randint(1, 20)
    if u != v:
        edges.append((u, v, w))

# Create video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/network_scans.mp4', fourcc, 10.0, (256, 256))

with open('/app/ground_truth_edges.txt', 'w') as f:
    for u, v, w in edges:
        f.write(f"{u},{v},{w}\n")
        img = qrcode.make(f"{u},{v},{w}")
        img = img.resize((256, 256))
        img_cv = cv2.cvtColor(np.array(img).astype(np.uint8)*255, cv2.COLOR_GRAY2BGR)
        out.write(img_cv)

out.release()
EOF

python3 /app/generate_video.py

cat << 'EOF' > /app/oracle_graph_query.c
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#define MAX_NODES 100

int graph[MAX_NODES][MAX_NODES];

void init_graph() {
    for (int i = 0; i < MAX_NODES; i++) {
        for (int j = 0; j < MAX_NODES; j++) {
            graph[i][j] = -1;
        }
    }
}

void load_graph() {
    FILE *f = fopen("/app/ground_truth_edges.txt", "r");
    if (!f) return;
    int u, v, w;
    while (fscanf(f, "%d,%d,%d", &u, &v, &w) == 3) {
        if (u < MAX_NODES && v < MAX_NODES) {
            graph[u][v] = w;
        }
    }
    fclose(f);
}

int dijkstra(int src, int dest) {
    if (src >= MAX_NODES || dest >= MAX_NODES) return -1;
    int dist[MAX_NODES];
    int visited[MAX_NODES];
    for (int i = 0; i < MAX_NODES; i++) {
        dist[i] = INT_MAX;
        visited[i] = 0;
    }
    dist[src] = 0;

    for (int count = 0; count < MAX_NODES - 1; count++) {
        int min = INT_MAX, u = -1;
        for (int i = 0; i < MAX_NODES; i++) {
            if (!visited[i] && dist[i] <= min) {
                min = dist[i];
                u = i;
            }
        }
        if (u == -1) break;
        visited[u] = 1;

        for (int v = 0; v < MAX_NODES; v++) {
            if (!visited[v] && graph[u][v] != -1 && dist[u] != INT_MAX && dist[u] + graph[u][v] < dist[v]) {
                dist[v] = dist[u] + graph[u][v];
            }
        }
    }
    return dist[dest] == INT_MAX ? -1 : dist[dest];
}

int main() {
    init_graph();
    load_graph();
    int src, dest;
    while (scanf("%d %d", &src, &dest) == 2) {
        printf("%d\n", dijkstra(src, dest));
    }
    return 0;
}
EOF

gcc -O3 /app/oracle_graph_query.c -o /app/oracle_graph_query

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
