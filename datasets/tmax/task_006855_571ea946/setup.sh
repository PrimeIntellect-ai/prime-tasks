#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/generate_data.py
import struct

with open('/home/user/dataset.bin', 'wb') as f:
    for i in range(12000):
        for j in range(5):
            val = (i * 5 + j) * 0.01
            f.write(struct.pack('f', val))
EOF
python3 /home/user/generate_data.py

cat << 'EOF' > /home/user/process_data.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>

using namespace std;

int main() {
    const int num_samples = 12000;
    const int num_features = 5;
    const int train_size = 10000;

    vector<vector<float>> data(num_samples, vector<float>(num_features));

    ifstream fin("/home/user/dataset.bin", ios::binary);
    if (!fin) {
        cerr << "Cannot open dataset.bin\n";
        return 1;
    }

    for (int i = 0; i < num_samples; ++i) {
        fin.read(reinterpret_cast<char*>(data[i].data()), num_features * sizeof(float));
    }
    fin.close();

    // Bug: Computing stats over the entire dataset
    vector<float> means(num_features, 0.0f);
    for (int i = 0; i < num_samples; ++i) {
        for (int j = 0; j < num_features; ++j) {
            means[j] += data[i][j];
        }
    }
    for (int j = 0; j < num_features; ++j) {
        means[j] /= num_samples;
    }

    vector<float> stddevs(num_features, 0.0f);
    for (int i = 0; i < num_samples; ++i) {
        for (int j = 0; j < num_features; ++j) {
            stddevs[j] += (data[i][j] - means[j]) * (data[i][j] - means[j]);
        }
    }
    for (int j = 0; j < num_features; ++j) {
        stddevs[j] = sqrt(stddevs[j] / num_samples);
    }

    // Normalize entire dataset
    for (int i = 0; i < num_samples; ++i) {
        for (int j = 0; j < num_features; ++j) {
            data[i][j] = (data[i][j] - means[j]) / stddevs[j];
        }
    }

    // Inference
    vector<float> weights = {0.5f, -0.2f, 0.1f, 0.8f, -0.5f};
    float bias = 0.1f;

    ofstream fout("/home/user/test_predictions.txt");
    fout << fixed << setprecision(4);

    // Wait, the user is supposed to output only the test set!
    // The buggy code might output all, let's make it output all and let the user fix it.
    for (int i = 0; i < num_samples; ++i) { // User needs to change this to i = train_size
        float pred = bias;
        for (int j = 0; j < num_features; ++j) {
            pred += data[i][j] * weights[j];
        }
        fout << pred << "\n";
    }
    fout.close();

    return 0;
}
EOF

chmod -R 777 /home/user
