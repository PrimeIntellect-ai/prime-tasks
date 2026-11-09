#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup.py
import numpy as np
import os

np.random.seed(42)

# Generate 100 matrices of 4x4
# Make some probabilities 0 to represent missing edges in the graph
matrices = []
for _ in range(100):
    mat = np.random.rand(4, 4)
    mat[0, 3] = 0.0 # No A->T
    mat[1, 1] = 0.0 # No C->C
    # Normalize rows
    row_sums = mat.sum(axis=1)
    mat = mat / row_sums[:, np.newaxis]
    matrices.append(mat)

with open("/home/user/matrices.txt", "w") as f:
    for mat in matrices:
        for row in mat:
            f.write(" ".join([f"{x:.6f}" for x in row]) + "\n")

# Generate sequence of 500 bases
# Avoid A->T and C->C to avoid -inf log probs
bases = ['A', 'C', 'G', 'T']
seq = ['A']
for _ in range(499):
    curr = seq[-1]
    if curr == 'A':
        seq.append(np.random.choice(['A', 'C', 'G']))
    elif curr == 'C':
        seq.append(np.random.choice(['A', 'G', 'T']))
    else:
        seq.append(np.random.choice(bases))

with open("/home/user/sequence.txt", "w") as f:
    f.write("".join(seq) + "\n")
EOF

python3 /home/user/setup.py

cat << 'EOF' > /home/user/calc_prob.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <iomanip>
#include <algorithm>

using namespace std;

int base_to_idx(char b) {
    if (b == 'A') return 0;
    if (b == 'C') return 1;
    if (b == 'G') return 2;
    if (b == 'T') return 3;
    return -1;
}

double calculate_prob(double mat[4][4], const string& seq) {
    double p = 1.0;
    for (size_t i = 1; i < seq.length(); ++i) {
        int u = base_to_idx(seq[i-1]);
        int v = base_to_idx(seq[i]);
        p *= mat[u][v];
    }
    return p;
}

int main() {
    double matrices[100][4][4];
    ifstream mfile("/home/user/matrices.txt");
    for (int m = 0; m < 100; ++m) {
        for (int i = 0; i < 4; ++i) {
            for (int j = 0; j < 4; ++j) {
                mfile >> matrices[m][i][j];
            }
        }
    }

    string sequence;
    ifstream sfile("/home/user/sequence.txt");
    sfile >> sequence;

    // BUGGY CODE:
    double prob = calculate_prob(matrices[0], sequence);
    cout << "Probability for matrix 0: " << prob << endl;

    // TODO: 
    // 1. Calculate log probabilities for all 100 matrices.
    // 2. Find the 95% bootstrap confidence interval.
    // 3. Write to /home/user/result.txt in the format [lower, upper]

    return 0;
}
EOF

chmod -R 777 /home/user
