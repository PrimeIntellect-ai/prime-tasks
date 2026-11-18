#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import json

# 1. Generate the graph data
random.seed(42)
os.makedirs("/home/user", exist_ok=True)
data_path = "/home/user/graph_export.jsonl"

num_nodes = 20000
edges = []
for i in range(1, num_nodes + 1):
    # Create 20-50 edges per node
    num_e = random.randint(20, 50)
    for _ in range(num_e):
        target = random.randint(1, num_nodes)
        weight = random.randint(1, 10)
        edges.append({"src": i, "dst": target, "weight": weight})

with open(data_path, "w") as f:
    for e in edges:
        f.write(json.dumps(e) + "\n")

# 2. Create the vendored C package
os.makedirs("/app/graph_backup_validator-1.0.0/src", exist_ok=True)

makefile_content = """CC=gcc
CFLAGS=-O0 -DDEBUG
validator: src/main.c src/query.c
\t$(CC) $(CFLAGS) src/main.c src/query.c -o validator
"""
with open("/app/graph_backup_validator-1.0.0/Makefile", "w") as f:
    f.write(makefile_content)

query_h = """#ifndef QUERY_H
#define QUERY_H

typedef struct {
    int src;
    int dst;
    int weight;
} Edge;

typedef struct {
    Edge *edges;
    int num_edges;
} GraphCtx;

void load_graph(const char *filename, GraphCtx *ctx);
void find_edges_from_node(GraphCtx *ctx, int node_id, Edge **out_start, int *out_count);
long long execute_2hop_aggregation(GraphCtx *ctx, int root_id);

#endif
"""
with open("/app/graph_backup_validator-1.0.0/src/query.h", "w") as f:
    f.write(query_h)

main_c = """#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "query.h"

void load_graph(const char *filename, GraphCtx *ctx) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        perror("Failed to open file");
        exit(1);
    }
    int capacity = 1000000;
    ctx->edges = malloc(capacity * sizeof(Edge));
    ctx->num_edges = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        int src, dst, weight;
        if (sscanf(line, "{\\"src\\": %d, \\"dst\\": %d, \\"weight\\": %d}", &src, &dst, &weight) == 3) {
            ctx->edges[ctx->num_edges].src = src;
            ctx->edges[ctx->num_edges].dst = dst;
            ctx->edges[ctx->num_edges].weight = weight;
            ctx->num_edges++;
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        return 1;
    }
    GraphCtx ctx;
    load_graph(argv[2], &ctx);

    int roots[] = {15, 1024, 5000, 9999};
    printf("root_id,aggregate_weight\\n");
    for(int i=0; i<4; i++) {
        long long weight = execute_2hop_aggregation(&ctx, roots[i]);
        printf("%d,%lld\\n", roots[i], weight);
    }
    return 0;
}
"""
with open("/app/graph_backup_validator-1.0.0/src/main.c", "w") as f:
    f.write(main_c)

query_c = """#include "query.h"

// INTENTIONAL PERTURBATION: Linear Scan
void find_edges_from_node(GraphCtx *ctx, int node_id, Edge **out_start, int *out_count) {
    int start_idx = -1;
    int count = 0;
    for(int i = 0; i < ctx->num_edges; i++) {
        if(ctx->edges[i].src == node_id) {
            if(start_idx == -1) start_idx = i;
            count++;
        }
    }
    if(start_idx != -1) {
        *out_start = &ctx->edges[start_idx];
        *out_count = count;
    } else {
        *out_count = 0;
    }
}

long long execute_2hop_aggregation(GraphCtx *ctx, int root_id) {
    Edge *hop1;
    int count1;
    long long total_weight = 0;

    find_edges_from_node(ctx, root_id, &hop1, &count1);
    for(int i = 0; i < count1; i++) {
        Edge *hop2;
        int count2;
        find_edges_from_node(ctx, hop1[i].dst, &hop2, &count2);
        for(int j = 0; j < count2; j++) {
            total_weight += hop1[i].weight + hop2[j].weight;
        }
    }
    return total_weight;
}
"""
with open("/app/graph_backup_validator-1.0.0/src/query.c", "w") as f:
    f.write(query_c)

# 3. Create the verification script
verify_py = """import time
import subprocess
import sys

def verify():
    start = time.time()
    proc = subprocess.run(
        ["/app/graph_backup_validator-1.0.0/validator", "--data", "/home/user/graph_export.jsonl", "--roots", "15,1024,5000,9999", "--depth", "2"],
        capture_output=True, text=True
    )
    elapsed = time.time() - start

    if proc.returncode != 0:
        print("Execution failed.")
        sys.exit(1)

    if elapsed > 0.25:
        print(f"Metric Threshold Failed: Execution took {elapsed:.4f}s. Threshold is 0.25s.")
        sys.exit(1)

    print(f"Metric Threshold Passed: Execution took {elapsed:.4f}s.")
    sys.exit(0)

if __name__ == '__main__':
    verify()
"""
with open("/home/user/verify.py", "w") as f:
    f.write(verify_py)

os.chmod("/home/user/verify.py", 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Compile initial unoptimized version
    cd /app/graph_backup_validator-1.0.0 && make

    chown -R user:user /app/graph_backup_validator-1.0.0
    chmod -R 777 /app/graph_backup_validator-1.0.0
    chmod -R 777 /home/user
