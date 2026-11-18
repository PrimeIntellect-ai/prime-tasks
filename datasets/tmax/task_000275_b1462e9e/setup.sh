#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl
    pip3 install pytest pandas scikit-learn numpy duckdb

    mkdir -p /app/data

    cat << 'EOF' > /app/generate_data.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)
n_edges = 10000
source_ids = np.random.randint(1, 1000, n_edges)
target_ids = np.random.randint(1, 1000, n_edges)
timestamps = np.random.randint(1600000000, 1610000000, n_edges)
weights = np.random.uniform(0.1, 10.0, n_edges)

df = pd.DataFrame({
    'source_id': source_ids,
    'target_id': target_ids,
    'timestamp': timestamps,
    'weight': weights
})
df.to_csv('/app/data/network.csv', index=False)

target_nodes = df['target_id'].unique()
results = []
for node in target_nodes:
    t_max = df[(df['source_id'] == node) | (df['target_id'] == node)]['timestamp'].max()
    window_df = df[(df['target_id'] == node) & (df['timestamp'] >= t_max - 604800) & (df['timestamp'] <= t_max)]
    score = window_df['weight'].sum()
    results.append({'node_id': node, 'impact_score': score})

golden_df = pd.DataFrame(results)
golden_df.to_csv('/app/golden_results.csv', index=False)
EOF

    python3 /app/generate_data.py

    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int node = atoi(argv[1]);
    FILE *f = fopen("/app/data/network.csv", "r");
    if (!f) return 1;

    char line[256];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return 1; }

    int s, t, ts;
    float w;
    int t_max = -1;

    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%d,%d,%d,%f", &s, &t, &ts, &w) == 4) {
            if (s == node || t == node) {
                if (ts > t_max) t_max = ts;
            }
        }
    }

    if (t_max == -1) {
        printf("0.0\n");
        fclose(f);
        return 0;
    }

    fseek(f, 0, SEEK_SET);
    if (!fgets(line, sizeof(line), f)) { fclose(f); return 1; }
    float sum = 0.0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "%d,%d,%d,%f", &s, &t, &ts, &w) == 4) {
            if (t == node && ts >= t_max - 604800 && ts <= t_max) {
                sum += w;
            }
        }
    }

    printf("%f\n", sum);
    fclose(f);
    return 0;
}
EOF

    gcc -O3 -static /app/oracle.c -o /app/graph_oracle
    strip --strip-all /app/graph_oracle
    upx /app/graph_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
