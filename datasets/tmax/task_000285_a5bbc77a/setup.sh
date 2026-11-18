#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create data.csv
    cat << 'EOF' > /home/user/data.csv
1,Alice,0
2,Bob,1
3,Charlie,1
4,David,2
5,Eve,2
6,Frank,3
EOF

    # Create vendored application
    mkdir -p /app/org-server

    cat << 'EOF' > /app/org-server/graph.h
#ifndef GRAPH_H
#define GRAPH_H

void add_edge(int manager, int employee);
char* get_descendants(int manager);

#endif
EOF

    cat << 'EOF' > /app/org-server/graph.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graph.h"

#define MAX_NODES 1000

int adj[MAX_NODES][MAX_NODES];
int deg[MAX_NODES];

void add_edge(int manager, int employee) {
    if (manager < MAX_NODES && employee < MAX_NODES) {
        adj[manager][deg[manager]++] = employee;
    }
}

// Bug: only direct subordinates
void get_descendants_helper(int node, int* result, int* count) {
    for (int i = 0; i < deg[node]; i++) {
        result[(*count)++] = adj[node][i];
        // Missing recursive call:
        // get_descendants_helper(adj[node][i], result, count);
    }
}

char* get_descendants(int manager) {
    int result[MAX_NODES];
    int count = 0;
    if (manager < MAX_NODES) {
        get_descendants_helper(manager, result, &count);
    }

    char* buf = malloc(MAX_NODES * 10);
    buf[0] = '\0';
    for (int i = 0; i < count; i++) {
        char tmp[16];
        sprintf(tmp, "%d%s", result[i], (i == count - 1) ? "" : ",");
        strcat(buf, tmp);
    }
    strcat(buf, "\n");
    return buf;
}
EOF

    cat << 'EOF' > /app/org-server/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "graph.h"

int main() {
    FILE* f = fopen("/home/user/hierarchy.csv", "r");
    if (!f) {
        perror("Failed to open hierarchy.csv");
        return 1;
    }
    int m, e;
    while (fscanf(f, "%d,%d", &m, &e) == 2) {
        add_edge(m, e);
    }
    fclose(f);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8888);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        int client_socket = accept(server_fd, NULL, NULL);
        if (client_socket < 0) continue;
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);
        int id;
        if (sscanf(buffer, "REPORTS %d", &id) == 1) {
            char* res = get_descendants(id);
            write(client_socket, res, strlen(res));
            free(res);
        }
        close(client_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/org-server/Makefile
all:
	gcc -o server server.c graph.c -lnotreal
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
