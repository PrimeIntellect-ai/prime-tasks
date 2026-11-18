#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils
    pip3 install pytest numpy pandas scikit-learn joblib

    mkdir -p /home/user/data
    mkdir -p /app
    mkdir -p /test_data

    # Generate the C++ code
    cat << 'EOF' > /app/feat_encode.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cmath>
#include <algorithm>

using namespace std;

void write_npy(const string& filename, const vector<vector<float>>& data) {
    ofstream out(filename, ios::binary);
    string dict = "{'descr': '<f4', 'fortran_order': False, 'shape': (" + to_string(data.size()) + ", 32), }";
    int remainder = 16 - (10 + dict.length() + 1) % 16;
    dict.append(remainder, ' ');
    dict += "\n";
    out << "\x93NUMPY\x01\x00";
    uint16_t header_len = dict.length();
    out.write(reinterpret_cast<char*>(&header_len), 2);
    out << dict;
    for (const auto& row : data) {
        out.write(reinterpret_cast<const char*>(row.data()), 32 * sizeof(float));
    }
}

int main(int argc, char* argv[]) {
    string input_file = "";
    string output_file = "";
    for (int i = 1; i < argc; ++i) {
        string arg = argv[i];
        if ((arg == "-i" || arg == "--input") && i + 1 < argc) {
            input_file = argv[++i];
        } else if ((arg == "-o" || arg == "--output") && i + 1 < argc) {
            output_file = argv[++i];
        }
    }

    if (input_file.empty() || output_file.empty()) {
        cerr << "Usage: " << argv[0] << " -i <input.csv> -o <output.npy>\n";
        return 1;
    }

    ifstream in(input_file);
    if (!in.is_open()) {
        cerr << "Failed to open input file.\n";
        return 1;
    }

    string line;
    getline(in, line); // skip header

    vector<vector<float>> embeddings;

    // Fixed random 3x32 matrix
    vector<vector<float>> W(3, vector<float>(32));
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 32; ++j) {
            W[i][j] = sin(i * 32 + j); // deterministic pseudo-random
        }
    }

    float means[3] = {1000.0, 50.0, 20.0};
    float stds[3] = {500.0, 25.0, 10.0};

    while (getline(in, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string token;
        getline(ss, token, ','); // user_id

        float feats[3] = {0, 0, 0};
        for (int i = 0; i < 3; ++i) {
            getline(ss, token, ',');
            feats[i] = stof(token);
            feats[i] = (feats[i] - means[i]) / stds[i];
        }

        vector<float> emb(32, 0.0f);
        for (int j = 0; j < 32; ++j) {
            for (int i = 0; i < 3; ++i) {
                emb[j] += feats[i] * W[i][j];
            }
            emb[j] = max(0.0f, emb[j]); // ReLU
        }
        embeddings.push_back(emb);
    }

    write_npy(output_file, embeddings);
    return 0;
}
EOF

    g++ -O3 /app/feat_encode.cpp -o /app/feat_encode
    strip /app/feat_encode
    rm /app/feat_encode.cpp

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd

np.random.seed(42)

n_users = 1000
user_ids = np.arange(1, n_users + 1)
total_amounts = np.random.normal(1000, 500, n_users).clip(min=10)
tx_counts = np.random.poisson(50, n_users).clip(min=1)
avg_amounts = total_amounts / tx_counts

# Generate transactions
tx_data = []
tx_id = 1
for i in range(n_users):
    u = user_ids[i]
    c = tx_counts[i]
    avg = avg_amounts[i]
    for _ in range(c):
        amt = np.random.normal(avg, avg * 0.2)
        tx_data.append([tx_id, u, amt, "2023-01-01 12:00:00"])
        tx_id += 1

tx_df = pd.DataFrame(tx_data, columns=['tx_id', 'user_id', 'amount', 'timestamp'])
tx_df.to_csv('/home/user/data/transactions.csv', index=False)

# Compute embeddings logic to generate targets
W = np.zeros((3, 32))
for i in range(3):
    for j in range(32):
        W[i, j] = np.sin(i * 32 + j)

means = np.array([1000.0, 50.0, 20.0])
stds = np.array([500.0, 25.0, 10.0])

feats = np.column_stack([total_amounts, tx_counts, avg_amounts])
feats_scaled = (feats - means) / stds
embs = np.maximum(0, feats_scaled @ W)

# True weights for LTV
true_w = np.random.normal(0, 1, 32)
ltv = embs @ true_w + np.random.normal(0, 1.0, n_users)

targets_df = pd.DataFrame({'user_id': user_ids, 'ltv': ltv})
targets_df.to_csv('/home/user/data/targets.csv', index=False)

# Test set
n_test = 200
test_total = np.random.normal(1000, 500, n_test).clip(min=10)
test_counts = np.random.poisson(50, n_test).clip(min=1)
test_avg = test_total / test_counts

test_feats = np.column_stack([test_total, test_counts, test_avg])
test_feats_scaled = (test_feats - means) / stds
test_embs = np.maximum(0, test_feats_scaled @ W)
test_ltv = test_embs @ true_w + np.random.normal(0, 1.0, n_test)

# Save as float32 to match C++ output
np.save('/test_data/hidden_test_embeddings.npy', test_embs.astype(np.float32))
np.save('/test_data/hidden_test_targets.npy', test_ltv)

EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
