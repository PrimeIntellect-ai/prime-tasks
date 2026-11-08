#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest scipy networkx

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import json
import random
import networkx as nx
from scipy import stats

base_dir = '/home/user/graph_research'
os.makedirs(f'{base_dir}/graphs', exist_ok=True)

# Generate C file
c_code = """#include <stdio.h>
#include <stdlib.h>

int find(int i, int *parent) {
    while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
    }
    return i;
}

void union_set(int i, int j, int *parent) {
    int root_i = find(i, parent);
    int root_j = find(j, parent);
    if (root_i != root_j) {
        parent[root_i] = root_j;
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    int V, E;
    if (fscanf(f, "%d %d", &V, &E) != 2) return 1;

    int *parent = malloc(V * sizeof(int));
    for (int i = 0; i < V; i++) parent[i] = i;

    for (int i = 0; i < E; i++) {
        int u, v;
        if (fscanf(f, "%d %d", &u, &v) == 2) {
            union_set(u, v, parent);
        }
    }
    fclose(f);

    int components = 0;
    for (int i = 0; i < V; i++) {
        if (parent[i] == i) components++;
    }
    printf("%d\\n", components);
    free(parent);
    return 0;
}
"""

with open(f'{base_dir}/union_find.c', 'w') as f:
    f.write(c_code)

random.seed(42)
sim_components = []

# Generate 50 graphs
for i in range(50):
    V = random.randint(20, 50)
    E = random.randint(15, 40)
    G = nx.gnm_random_graph(V, E, seed=42+i)
    # Using python's exact component count as ground truth
    comps = nx.number_connected_components(G)
    sim_components.append(comps)

    with open(f'{base_dir}/graphs/graph_{i}.txt', 'w') as f:
        f.write(f"{V} {E}\n")
        for u, v in G.edges():
            f.write(f"{u} {v}\n")

# Generate reference data
random.seed(100)
ref_components = [max(1, c + random.randint(0, 3)) for c in sim_components]

with open(f'{base_dir}/reference_data.json', 'w') as f:
    json.dump({"components": ref_components}, f)

# Compute ground truth answers
t_stat, p_val = stats.ttest_ind(sim_components, ref_components, equal_var=False)
sim_mean = sum(sim_components) / len(sim_components)
ref_mean = sum(ref_components) / len(ref_components)

# Save expected truth for test suite (not accessible to agent)
os.makedirs('/root/truth', exist_ok=True)
with open('/root/truth/expected.json', 'w') as f:
    json.dump({
        "t_statistic": t_stat,
        "p_value": p_val,
        "simulated_mean": sim_mean,
        "reference_mean": ref_mean
    }, f)
EOF

    # Execute setup script
    python3 /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
