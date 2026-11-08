#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_c
    cat << 'EOF' > /home/user/legacy_c/graph.h
#ifndef GRAPH_H
#define GRAPH_H

int get_children(int node_id, int* out_children, int max_children);

#endif
EOF

    cat << 'EOF' > /home/user/legacy_c/graph.c
#include "graph.h"

int get_children(int node_id, int* out_children, int max_children) {
    int count = 0;
    if (node_id == 1) {
        if (max_children >= 2) { out_children[0] = 2; out_children[1] = 3; count = 2; }
    } else if (node_id == 2) {
        if (max_children >= 2) { out_children[0] = 4; out_children[1] = 5; count = 2; }
    } else if (node_id == 3) {
        if (max_children >= 1) { out_children[0] = 6; count = 1; }
    } else if (node_id == 4) {
        if (max_children >= 1) { out_children[0] = 7; count = 1; }
    } else if (node_id == 5) {
        if (max_children >= 1) { out_children[0] = 7; count = 1; }
    } else if (node_id == 6) {
        if (max_children >= 1) { out_children[0] = 7; count = 1; }
    } else if (node_id == 7) {
        if (max_children >= 1) { out_children[0] = 8; count = 1; }
    }
    return count;
}
EOF

    cd /home/user/legacy_c
    gcc -shared -o libgraph.so -fPIC graph.c

    chmod -R 777 /home/user
