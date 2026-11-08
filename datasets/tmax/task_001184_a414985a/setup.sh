#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate the true graph edges and oracle
    cat << 'EOF' > generate_video.py
import subprocess
import os

edges = [
    (10, 20), (20, 30), (30, 40), (10, 50), (50, 30),
    (40, 60), (30, 60), (60, 70), (70, 80), (80, 90),
    (90, 100), (100, 110), (110, 120), (120, 130),
    (10, 15), (15, 20), (20, 25), (25, 30)
]
# Pad to 120 frames with dummy self-loops or repeats
while len(edges) < 120:
    edges.append((255, 255))

with open('raw_frames.bin', 'wb') as f:
    for u, v in edges:
        f.write(bytes([u, v]))

subprocess.run([
    'ffmpeg', '-y', '-f', 'rawvideo', '-s', '2x1', '-pix_fmt', 'gray', '-r', '10',
    '-i', 'raw_frames.bin', '-c:v', 'libx264rgb', '-crf', '0', 'dataset_video.mp4'
])
EOF
    python3 generate_video.py

    # Create the Oracle
    cat << 'EOF' > oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 256

int adj[MAX_NODES][MAX_NODES];
int deg[MAX_NODES];

int compare_ints(const void* a, const void* b) {
    return (*(int*)a - *(int*)b);
}

void bfs(int start, int end) {
    if (start == end) {
        printf("Path: %d\n", start);
        return;
    }
    int dist[MAX_NODES];
    int parent[MAX_NODES];
    for (int i=0; i<MAX_NODES; i++) { dist[i] = -1; parent[i] = -1; }

    int queue[MAX_NODES];
    int head = 0, tail = 0;

    queue[tail++] = start;
    dist[start] = 0;

    while (head < tail) {
        int u = queue[head++];
        for (int i=0; i<deg[u]; i++) {
            int v = adj[u][i];
            if (dist[v] == -1) {
                dist[v] = dist[u] + 1;
                parent[v] = u;
                queue[tail++] = v;
            } else if (dist[v] == dist[u] + 1) {
                if (u < parent[v]) {
                    parent[v] = u;
                }
            }
        }
    }

    if (dist[end] == -1) {
        printf("NONE\n");
    } else {
        int path[MAX_NODES];
        int c = 0;
        int curr = end;
        while (curr != -1) {
            path[c++] = curr;
            curr = parent[curr];
        }
        printf("Path: ");
        for (int i=c-1; i>=0; i--) {
            printf("%d%s", path[i], i==0 ? "" : "->");
        }
        printf("\n");
    }
}

int main() {
    FILE *f = fopen("/home/user/edges.txt", "r");
    if (!f) exit(1);
    int u, v;
    while (fscanf(f, "%d %d", &u, &v) == 2) {
        int exists = 0;
        for(int i=0; i<deg[u]; i++) { if(adj[u][i] == v) exists = 1; }
        if (!exists) adj[u][deg[u]++] = v;
    }
    fclose(f);

    for (int i=0; i<MAX_NODES; i++) {
        if (deg[i] > 1) qsort(adj[i], deg[i], sizeof(int), compare_ints);
    }

    while (scanf("%d %d", &u, &v) == 2) {
        bfs(u, v);
    }
    return 0;
}
EOF
    gcc -O2 oracle.c -o oracle
    chmod +x oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
