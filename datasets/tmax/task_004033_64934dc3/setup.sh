#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        gcc \
        build-essential

    pip3 install pytest pillow

    # Create oracle checker
    cat << 'EOF' > /opt/oracle_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#define MAX_V 1005
#define INF INT_MAX

typedef struct Edge {
    int to;
    int weight;
    struct Edge* next;
} Edge;

Edge* graph[MAX_V];

void add_edge(int u, int v, int w) {
    Edge* e = (Edge*)malloc(sizeof(Edge));
    e->to = v;
    e->weight = w;
    e->next = graph[u];
    graph[u] = e;
}

int dist[MAX_V];
int visited[MAX_V];

void dijkstra(int start, int V) {
    for (int i = 0; i < V; i++) {
        dist[i] = INF;
        visited[i] = 0;
    }
    dist[start] = 0;

    for (int i = 0; i < V; i++) {
        int u = -1;
        for (int j = 0; j < V; j++) {
            if (!visited[j] && (u == -1 || dist[j] < dist[u])) {
                u = j;
            }
        }
        if (dist[u] == INF) break;
        visited[u] = 1;

        for (Edge* e = graph[u]; e != NULL; e = e->next) {
            int v = e->to;
            int weight = e->weight;
            if (dist[u] + weight < dist[v]) {
                dist[v] = dist[u] + weight;
            }
        }
    }
}

int main() {
    int V, E;
    if (scanf("%d %d", &V, &E) != 2) return 0;
    for (int i = 0; i < V; i++) graph[i] = NULL;
    for (int i = 0; i < E; i++) {
        int u, v, w;
        if (scanf("%d %d %d", &u, &v, &w) != 3) return 0;
        add_edge(u, v, w);
    }
    int Q;
    if (scanf("%d", &Q) != 1) return 0;
    for (int i = 0; i < Q; i++) {
        int start, target;
        if (scanf("%d %d", &start, &target) != 2) return 0;
        dijkstra(start, V);
        if (dist[target] == INF) {
            printf("-1\n");
        } else {
            printf("%d\n", dist[target]);
        }
    }
    return 0;
}
EOF
    gcc -O3 /opt/oracle_checker.c -o /opt/oracle_checker
    chmod +x /opt/oracle_checker

    # Generate video
    mkdir -p /app
    cd /app
    cat << 'EOF' > generate_frames.py
from PIL import Image, ImageDraw
import os

for i in range(10):
    img = Image.new('RGB', (800, 600), color=(255, 255, 255))
    d = ImageDraw.Draw(img)
    text = f"ACCESS: {i} -> {i+1} {i*5+5}"
    # Use default font, scale it up by drawing multiple times or just accept small text
    # Tesseract can usually read it if it's clear
    d.text((100, 250), text, fill=(0, 0, 0))
    img.save(f"frame_{i:03d}.png")
EOF
    python3 generate_frames.py
    ffmpeg -framerate 1 -i frame_%03d.png -c:v libx264 -r 1 -pix_fmt yuv420p access_logs.mp4
    rm frame_*.png generate_frames.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
