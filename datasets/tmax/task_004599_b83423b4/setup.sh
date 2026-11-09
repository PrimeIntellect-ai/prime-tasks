#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# 1. Generate Raw Data
np.random.seed(42)
data = np.random.randn(20, 5) * 10 + 50  # 20 items, 5 features

# Inject missing values (-999.0)
data[2, 1] = -999.0
data[10, 3] = -999.0
data[15, 0] = -999.0

# Inject outliers
data[5, 2] = 10000.0  # High outlier
data[18, 4] = -5000.0 # Low outlier

np.savetxt('/home/user/raw_items.csv', data, delimiter=',', fmt='%.4f')

# 2. Compute expected truth for verification
clean_data = data.copy()
for c in range(5):
    col = clean_data[:, c]
    valid_mask = col != -999.0
    valid_vals = col[valid_mask]
    mean = np.mean(valid_vals)
    std = np.std(valid_vals, ddof=0)

    # Impute
    col[~valid_mask] = mean

    # Clip
    col = np.clip(col, mean - 3*std, mean + 3*std)
    clean_data[:, c] = col

# Projection matrix (fixed for reproducibility)
proj = np.array([
    [ 0.5, -0.2,  0.1],
    [-0.1,  0.6,  0.3],
    [ 0.4,  0.4, -0.5],
    [-0.3,  0.1,  0.8],
    [ 0.2, -0.7,  0.2]
])

embeddings = clean_data.dot(proj)

# Find top 3 neighbors for index 0
dists = np.linalg.norm(embeddings - embeddings[0], axis=1)
dists[0] = np.inf # Exclude self
top3 = np.argsort(dists)[:3]

with open('/home/user/expected_top3.txt', 'w') as f:
    f.write(",".join(map(str, top3)) + "\n")

# 3. Write buggy C++ code
cpp_code = """#include <iostream>
#include <fstream>
#include <vector>
#include <sstream>
#include <string>
#include <cmath>
#include <iomanip>

using namespace std;

int main() {
    vector<vector<double>> data;
    ifstream file("/home/user/raw_items.csv");
    string line;
    while (getline(file, line)) {
        vector<double> row;
        stringstream ss(line);
        string val;
        while (getline(ss, val, ',')) {
            row.push_back(stod(val));
        }
        data.push_back(row);
    }

    // TODO: Implement missing value handling (-999.0) and outlier clipping (mean +/- 3*std) here.


    // Fixed Projection Matrix (5D to 3D)
    vector<vector<double>> proj = {
        { 0.5, -0.2,  0.1},
        {-0.1,  0.6,  0.3},
        { 0.4,  0.4, -0.5},
        {-0.3,  0.1,  0.8},
        { 0.2, -0.7,  0.2}
    };

    // Project and write
    ofstream out("/home/user/clean_embeddings.csv");
    vector<vector<double>> embeddings;

    for (size_t i = 0; i < data.size(); ++i) {
        vector<double> emb(3, 0.0);
        for (int j = 0; j < 3; ++j) {
            for (int k = 0; k < 5; ++k) {
                emb[j] += data[i][k] * proj[k][j];
            }
        }
        embeddings.push_back(emb);
        out << fixed << setprecision(4) << emb[0] << "," << emb[1] << "," << emb[2] << "\\n";
    }

    // TODO: Calculate top 3 most similar items to item 0 using Euclidean distance
    // Write indices to /home/user/top3_similar.txt

    return 0;
}
"""
with open('/home/user/embed_pipeline.cpp', 'w') as f:
    f.write(cpp_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
