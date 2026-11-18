#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'CHECKER_EOF' > /tmp/check_large.cpp
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;

struct DSU {
    vector<int> parent, size, minimum;
    explicit DSU(int n) : parent(n + 1), size(n + 1, 1), minimum(n + 1) {
        for (int i = 0; i <= n; ++i) parent[i] = minimum[i] = i;
    }
    int find(int x) {
        int r = x;
        while (parent[r] != r) r = parent[r];
        while (parent[x] != x) {
            int next = parent[x];
            parent[x] = r;
            x = next;
        }
        return r;
    }
    void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (size[a] < size[b]) swap(a, b);
        parent[b] = a;
        size[a] += size[b];
        minimum[a] = min(minimum[a], minimum[b]);
    }
};

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    const int max_node = stoi(argv[3]);
    DSU dsu(max_node);
    vector<int> degree(max_node + 1, 0);
    vector<unsigned char> seen(max_node + 1, 0);

    FILE *in = fopen(argv[1], "r");
    if (!in) return 3;
    char header[256];
    if (!fgets(header, sizeof(header), in)) return 4;
    int u, v;
    long long edges = 0;
    while (fscanf(in, "%d,%d", &u, &v) == 2) {
        if (u < 1 || u > max_node || v < 1 || v > max_node) return 5;
        seen[u] = seen[v] = 1;
        ++degree[u];
        ++degree[v];
        dsu.unite(u, v);
        ++edges;
    }
    fclose(in);
    if (edges != 5000000) return 6;

    unordered_map<int, vector<int>> component_degrees;
    component_degrees.reserve(max_node / 8);
    for (int node = 1; node <= max_node; ++node) {
        if (seen[node]) component_degrees[dsu.find(node)].push_back(degree[node]);
    }
    for (auto &entry : component_degrees) {
        auto &values = entry.second;
        sort(values.begin(), values.end(), greater<int>());
        values.erase(unique(values.begin(), values.end()), values.end());
    }

    ifstream out(argv[2]);
    if (!out) return 7;
    string line;
    if (!getline(out, line)) return 8;
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line != "node,component_id,degree,rank") return 9;

    for (int node = 1; node <= max_node; ++node) {
        if (!seen[node]) continue;
        if (!getline(out, line)) return 10;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        long long got_node, got_component, got_degree, got_rank;
        char extra;
        int fields = sscanf(line.c_str(), "%lld,%lld,%lld,%lld%c",
                            &got_node, &got_component, &got_degree, &got_rank, &extra);
        if (fields != 4) return 11;
        int root = dsu.find(node);
        int expected_component = dsu.minimum[root];
        const auto &values = component_degrees[root];
        int expected_rank = int(lower_bound(values.begin(), values.end(), degree[node], greater<int>()) - values.begin()) + 1;
        if (got_node != node || got_component != expected_component ||
            got_degree != degree[node] || got_rank != expected_rank) {
            cerr << "Mismatch at node " << node << endl;
            return 12;
        }
    }
    while (getline(out, line)) {
        if (line.find_first_not_of(" \t\r\n") != string::npos) return 13;
    }
    return 0;
}
CHECKER_EOF

g++ -O3 -std=c++17 /tmp/check_large.cpp -o /tmp/check_large

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import pytest
import pandas as pd
import numpy as np


def generate_graph(num_nodes, num_edges, output_path, seed=42):
    if seed is None:
        rng = np.random.default_rng()
        sources = rng.integers(1, num_nodes + 1, num_edges, dtype=np.int32)
        targets = rng.integers(1, num_nodes + 1, num_edges, dtype=np.int32)
    else:
        rng = np.random.RandomState(seed)
        sources = rng.randint(1, num_nodes + 1, num_edges)
        targets = rng.randint(1, num_nodes + 1, num_edges)
    df = pd.DataFrame({'source': sources, 'target': targets})
    df.to_csv(output_path, index=False)
    present = np.zeros(num_nodes + 1, dtype=np.bool_)
    present[sources] = True
    present[targets] = True
    return int(present.sum())


def test_fast_graph_exists():
    binary_path = "/home/user/fast_graph"
    source_path = "/home/user/fast_graph.cpp"
    assert os.path.exists(binary_path), f"Expected binary {binary_path} does not exist."
    assert os.path.isfile(binary_path), f"Expected {binary_path} to be a file."
    assert os.access(binary_path, os.X_OK), f"Expected {binary_path} to be executable."
    assert os.path.isfile(source_path), f"Expected C++ source {source_path} does not exist."
    assert subprocess.run(["cmp", "-s", binary_path, "/app/graph_oracle"]).returncode != 0, \
        "Submission must not be a byte-identical copy of graph_oracle."


def test_correctness_against_oracle():
    input_csv = "/tmp/small_graph.csv"
    oracle_out = "/tmp/oracle_small_out.csv"
    fast_out = "/tmp/fast_small_out.csv"

    generate_graph(10_000, 50_000, input_csv)
    subprocess.run(["/app/graph_oracle", input_csv, oracle_out], check=True)
    subprocess.run(["/home/user/fast_graph", input_csv, fast_out], check=True)

    df_expected = pd.read_csv(oracle_out)
    df_actual = pd.read_csv(fast_out)
    pd.testing.assert_frame_equal(df_expected, df_actual, check_dtype=False,
                                  obj="Correctness on small graph")


def test_performance():
    input_csv = "/tmp/large_graph.csv"
    fast_out = "/tmp/fast_large_out.csv"

    # Entropy-backed generation prevents recognizing one fixed large input.
    num_unique_nodes = generate_graph(1_000_000, 5_000_000, input_csv, seed=None)

    start_time = time.time()
    subprocess.run(["/home/user/fast_graph", input_csv, fast_out], check=True)
    duration = time.time() - start_time

    assert duration <= 2.0, \
        f"Performance failed: execution took {duration:.2f} seconds (threshold is 2.0s)."

    # Preserve the original large-output sanity assertions.
    df_actual = pd.read_csv(fast_out)
    assert len(df_actual) == num_unique_nodes, \
        f"Expected {num_unique_nodes} rows in output, got {len(df_actual)}."
    assert list(df_actual.columns) == ["node", "component_id", "degree", "rank"], \
        "Output columns are incorrect."

    # Independently derive and check every expected value on the timed 5M-edge case.
    subprocess.run(["/tmp/check_large", input_csv, fast_out, "1000000"], check=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
