#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev wget

pip3 install pytest numpy scipy

mkdir -p /app
mkdir -p /home/user

cat << 'EOF' > /tmp/ref.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <cmath>
#include <algorithm>

using namespace std;

void read_bin(const char* path, vector<vector<float>>& data, int dim) {
    ifstream f(path, ios::binary);
    f.seekg(0, ios::end);
    size_t size = f.tellg();
    f.seekg(0, ios::beg);
    int num = size / (dim * sizeof(float));
    data.resize(num, vector<float>(dim));
    for(int i=0; i<num; ++i) {
        f.read((char*)data[i].data(), dim * sizeof(float));
    }
}

int main(int argc, char** argv) {
    if(argc != 3) return 1;
    vector<vector<float>> dataset, queries;
    read_bin(argv[1], dataset, 128);
    read_bin(argv[2], queries, 128);

    for(size_t i=0; i<queries.size(); ++i) {
        vector<pair<float, int>> dists;
        dists.reserve(dataset.size());
        for(size_t j=0; j<dataset.size(); ++j) {
            float d = 0;
            for(int k=0; k<128; ++k) {
                float diff = queries[i][k] - dataset[j][k];
                d += diff * diff;
            }
            dists.push_back({d, j});
        }
        sort(dists.begin(), dists.end());
        for(int k=0; k<10; ++k) {
            cout << dists[k].second << (k==9 ? "" : " ");
        }
        cout << "\n";
    }
    return 0;
}
EOF

g++ -O3 /tmp/ref.cpp -o /app/ref_search
strip /app/ref_search

cat << 'EOF' > /tmp/gen_data.py
import numpy as np
np.random.seed(42)
dataset = np.random.randn(10000, 128).astype(np.float32)
queries = np.random.randn(100, 128).astype(np.float32)
dataset.tofile('/home/user/dataset.bin')
queries.tofile('/home/user/queries.bin')
EOF

python3 /tmp/gen_data.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
