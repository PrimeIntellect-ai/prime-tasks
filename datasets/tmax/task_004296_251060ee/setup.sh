#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/router.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 1000
char nodes[MAX_NODES][64];
int adj[MAX_NODES][MAX_NODES];
int adj_count[MAX_NODES];
int num_nodes = 0;

int get_node(char *name) {
    for(int i=0; i<num_nodes; i++) {
        if(strcmp(nodes[i], name) == 0) return i;
    }
    strcpy(nodes[num_nodes], name);
    return num_nodes++;
}

int main(int argc, char **argv) {
    if(argc != 4) return 1;
    FILE *f = fopen(argv[1], "r");
    if(!f) return 1;

    char line[256];
    int current_node = -1;
    while(fgets(line, sizeof(line), f)) {
        char type[64], val[64];
        if(sscanf(line, "%s %s", type, val) == 2) {
            if(strcmp(type, "BACKUP_START") == 0) {
                current_node = get_node(val);
            } else if(strcmp(type, "DEPENDS_ON") == 0 && current_node != -1) {
                int dep = get_node(val);
                adj[current_node][adj_count[current_node]++] = dep;
            }
        }
    }
    fclose(f);

    int src = get_node(argv[2]);
    int tgt = get_node(argv[3]);

    if(src == tgt) { printf("0\n"); return 0; }

    int q[MAX_NODES], head = 0, tail = 0;
    int dist[MAX_NODES];
    for(int i=0; i<MAX_NODES; i++) dist[i] = -1;

    q[tail++] = src;
    dist[src] = 0;

    while(head < tail) {
        int u = q[head++];
        if(u == tgt) break;
        for(int i=0; i<adj_count[u]; i++) {
            int v = adj[u][i];
            if(dist[v] == -1) {
                dist[v] = dist[u] + 1;
                q[tail++] = v;
            }
        }
    }

    if(dist[tgt] == -1) printf("UNREACHABLE\n");
    else printf("%d\n", dist[tgt]);

    return 0;
}
EOF
    gcc -O2 /tmp/router.c -o /app/backup_router
    strip /app/backup_router
    rm /tmp/router.c
    chmod +x /app/backup_router

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
