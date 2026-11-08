#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Generate graph_data.bin
    cat << 'EOF' > /tmp/gen_graph.py
import struct
import random

random.seed(42)
with open('/home/user/graph_data.bin', 'wb') as f:
    # Create some dense clusters
    for _ in range(100000):
        u = random.randint(0, 100)
        v = random.randint(0, 100)
        f.write(struct.pack('<II', u, v))
    for _ in range(400000):
        u = random.randint(0, 100000)
        v = random.randint(0, 100000)
        f.write(struct.pack('<II', u, v))
EOF
    python3 /tmp/gen_graph.py

    # Create legacy backup tool
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define MAX_NODES 200000

int visited[MAX_NODES] = {0};
int result[MAX_NODES];
int result_count = 0;

int compare(const void *a, const void *b) {
    return (*(int*)a - *(int*)b);
}

int main(int argc, char **argv) {
    if (argc != 5) return 1;
    uint32_t root = atoi(argv[1]);
    int max_depth = atoi(argv[2]);
    int page_size = atoi(argv[3]);
    int page_num = atoi(argv[4]);

    uint32_t *frontier = malloc(MAX_NODES * sizeof(uint32_t));
    uint32_t *next_frontier = malloc(MAX_NODES * sizeof(uint32_t));
    int f_count = 0;
    int nf_count = 0;

    if (root < MAX_NODES) {
        frontier[f_count++] = root;
        visited[root] = 1;
        result[result_count++] = root;
    }

    for (int d = 0; d < max_depth; d++) {
        nf_count = 0;
        for (int i = 0; i < f_count; i++) {
            uint32_t u = frontier[i];
            FILE *f = fopen("/home/user/graph_data.bin", "rb");
            if (!f) continue;
            uint32_t edge[2];
            while (fread(edge, sizeof(uint32_t), 2, f) == 2) {
                if (edge[0] == u) {
                    uint32_t v = edge[1];
                    if (v < MAX_NODES && !visited[v]) {
                        visited[v] = 1;
                        next_frontier[nf_count++] = v;
                        result[result_count++] = v;
                    }
                }
            }
            fclose(f);
            // Artificial delay to ensure it's slow enough
            for(volatile int delay=0; delay<50000; delay++);
        }
        memcpy(frontier, next_frontier, nf_count * sizeof(uint32_t));
        f_count = nf_count;
    }

    qsort(result, result_count, sizeof(int), compare);

    int start_idx = page_size * page_num;
    int end_idx = start_idx + page_size;
    if (end_idx > result_count) end_idx = result_count;
    if (start_idx > result_count) start_idx = result_count;

    printf("{\"root\": %u, \"depth\": %d, \"total_reachable\": %d, \"page\": %d, \"results\": [", root, max_depth, result_count, page_num);
    for (int i = start_idx; i < end_idx; i++) {
        printf("%d%s", result[i], (i == end_idx - 1) ? "" : ", ");
    }
    printf("]}\n");

    free(frontier);
    free(next_frontier);
    return 0;
}
EOF

    gcc -O0 /tmp/legacy.c -o /app/legacy_backup_bin
    strip -s /app/legacy_backup_bin
    rm /tmp/legacy.c /tmp/gen_graph.py

    chmod -R 777 /home/user
    chmod -R 777 /app
