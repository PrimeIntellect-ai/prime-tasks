#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np

np.random.seed(42)
# Generate 100 rows, 3 columns
X = np.random.randn(100, 3) * 5.0 + 10.0

with open('/home/user/data/embeddings.csv', 'w') as f:
    for row in X:
        f.write(','.join(map(str, row)) + '\n')
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    cat << 'EOF' > /home/user/pipeline.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cmath>
#include <iomanip>

using namespace std;

int main() {
    ifstream infile("/home/user/data/embeddings.csv");
    string line;
    vector<vector<double>> data;
    while (getline(infile, line)) {
        stringstream ss(line);
        string val;
        vector<double> row;
        while (getline(ss, val, ',')) {
            row.push_back(stod(val));
        }
        data.push_back(row);
    }

    int n = data.size();
    int cols = data[0].size();

    // FLAWED: Computing stats on entire dataset
    vector<double> means(cols, 0.0);
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < cols; j++) means[j] += data[i][j];
    }
    for (int j = 0; j < cols; j++) means[j] /= n;

    vector<double> stds(cols, 0.0);
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < cols; j++) stds[j] += pow(data[i][j] - means[j], 2);
    }
    for (int j = 0; j < cols; j++) stds[j] = sqrt(stds[j] / n);

    // FLAWED: Normalizing everything with global stats
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < cols; j++) data[i][j] = (data[i][j] - means[j]) / stds[j];
    }

    // Split and save
    ofstream train_out("/home/user/train_norm.csv");
    ofstream test_out("/home/user/test_norm.csv");
    train_out << fixed << setprecision(6);
    test_out << fixed << setprecision(6);

    for (int i = 0; i < 80; i++) {
        for (int j = 0; j < cols; j++) {
            train_out << data[i][j] << (j == cols - 1 ? "" : ",");
        }
        train_out << "\n";
    }

    for (int i = 80; i < n; i++) {
        for (int j = 0; j < cols; j++) {
            test_out << data[i][j] << (j == cols - 1 ? "" : ",");
        }
        test_out << "\n";
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
