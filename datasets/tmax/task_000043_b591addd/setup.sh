#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/api_responses

cat << 'EOF' > /home/user/api_responses/task1.json
{"id": "DataFetch", "requires": ["AuthService"]}
EOF

cat << 'EOF' > /home/user/api_responses/task2.json
{"id": "DataClean", "requires": ["DataFetch"]}
EOF

cat << 'EOF' > /home/user/api_responses/task3.json
{"id": "ModelTrain", "requires": ["DataClean", "FeatureEng"]}
EOF

cat << 'EOF' > /home/user/api_responses/task4.json
{"id": "FeatureEng", "requires": ["DataFetch"]}
EOF

cat << 'EOF' > /home/user/api_responses/task5.json
{"id": "AuthService", "requires": []}
EOF

cat << 'EOF' > /home/user/libgraph.c
#include <stdlib.h>

int* resolve_dependencies(int num_nodes, int num_edges, int* edge_u, int* edge_v) {
    int* in_degree = (int*)calloc(num_nodes, sizeof(int));
    for(int i=0; i<num_edges; i++) {
        in_degree[edge_v[i]]++;
    }

    int* queue = (int*)malloc(num_nodes * sizeof(int));
    int head = 0, tail = 0;

    for(int i=0; i<num_nodes; i++) {
        if(in_degree[i] == 0) queue[tail++] = i;
    }

    // BUG: Allocates num_nodes, but writes num_nodes + 1 elements
    int* result = (int*)malloc(num_nodes * sizeof(int)); 
    int count = 0;

    while(head < tail) {
        int u = queue[head++];
        result[count++] = u;

        for(int i=0; i<num_edges; i++) {
            if(edge_u[i] == u) {
                in_degree[edge_v[i]]--;
                if(in_degree[edge_v[i]] == 0) {
                    queue[tail++] = edge_v[i];
                }
            }
        }
    }

    free(in_degree);
    free(queue);

    result[num_nodes] = -1; // Sentinel value write causes out-of-bounds

    return result;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
