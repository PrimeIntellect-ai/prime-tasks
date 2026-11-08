#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy pandas

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /app

    # Generate raw data
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)
n = 1000
target = np.random.randn(n)

# Good features
f1 = target + np.random.randn(n)*0.1
f2 = target * 2 + np.random.randn(n)*0.2
f3 = -target + np.random.randn(n)*0.1
f4 = target**2 + np.random.randn(n)*0.1
f5 = np.sin(target) + np.random.randn(n)*0.1

# Noise features
f6_10 = np.random.randn(n, 5)

# Redundant/collinear features
f11_15 = np.array([f1, f2, f3, f4, f5]).T + np.random.randn(n, 5)*0.01

data = np.column_stack([target, f1, f2, f3, f4, f5, f6_10, f11_15])
cols = ['target'] + [f'f{i}' for i in range(1, 16)]
df = pd.DataFrame(data, columns=cols)

# Inject missing values
for col in cols:
    df.loc[np.random.choice(n, 50, replace=False), col] = np.nan

# Inject extreme outliers
for col in cols:
    df.loc[np.random.choice(n, 10, replace=False), col] = 9999.0

df.to_csv('/home/user/data/raw.csv', index=False)
EOF
    python3 /tmp/generate_data.py

    # Create C++ evaluator
    cat << 'EOF' > /tmp/evaluator.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cmath>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    ifstream file(argv[1]);
    if (!file.is_open()) return 1;

    string line;
    if (!getline(file, line)) return 1;

    stringstream ss(line);
    string col;
    vector<string> headers;
    int target_idx = -1;
    while (getline(ss, col, ',')) {
        if (!col.empty() && col.back() == '\r') col.pop_back();
        headers.push_back(col);
        if (col == "target") target_idx = headers.size() - 1;
    }

    if (target_idx == -1) {
        cout << "0.000" << endl;
        return 0;
    }

    vector<vector<double>> data(headers.size());
    while (getline(file, line)) {
        if (line.empty()) continue;
        stringstream ss2(line);
        string val;
        int c = 0;
        while (getline(ss2, val, ',')) {
            if (!val.empty() && val.back() == '\r') val.pop_back();
            if (val.empty()) {
                cout << "0.000" << endl;
                return 0;
            }
            try {
                data[c].push_back(stod(val));
            } catch (...) {
                cout << "0.000" << endl;
                return 0;
            }
            c++;
        }
        if (c != headers.size()) {
            cout << "0.000" << endl;
            return 0;
        }
    }

    int n = data[0].size();
    if (n == 0) { cout << "0.000" << endl; return 0; }

    vector<double> means(headers.size(), 0.0);
    vector<double> stds(headers.size(), 0.0);

    for (size_t i = 0; i < headers.size(); i++) {
        double sum = 0;
        for (double v : data[i]) sum += v;
        means[i] = sum / n;
        double sq_sum = 0;
        for (double v : data[i]) sq_sum += (v - means[i]) * (v - means[i]);
        stds[i] = sqrt(sq_sum / n);

        for (double v : data[i]) {
            if (v > means[i] + 5 * stds[i]) {
                cout << "0.000" << endl;
                return 0;
            }
        }
    }

    auto corr = [&](int i, int j) {
        double cov = 0;
        for (int k = 0; k < n; k++) {
            cov += (data[i][k] - means[i]) * (data[j][k] - means[j]);
        }
        if (stds[i] == 0 || stds[j] == 0) return 0.0;
        return abs(cov / (n * stds[i] * stds[j]));
    };

    double mean_target_corr = 0;
    int target_count = 0;
    for (size_t i = 0; i < headers.size(); i++) {
        if (i == target_idx) continue;
        mean_target_corr += corr(i, target_idx);
        target_count++;
    }
    if (target_count > 0) mean_target_corr /= target_count;

    double mean_collinearity = 0;
    int coll_count = 0;
    for (size_t i = 0; i < headers.size(); i++) {
        if (i == target_idx) continue;
        for (size_t j = 0; j < headers.size(); j++) {
            if (j == target_idx || i == j) continue;
            mean_collinearity += corr(i, j);
            coll_count++;
        }
    }
    if (coll_count > 0) mean_collinearity /= coll_count;

    double score = mean_target_corr - mean_collinearity;
    cout << score << endl;
    return 0;
}
EOF

    g++ -O3 /tmp/evaluator.cpp -o /app/evaluator
    strip -s /app/evaluator
    chmod +x /app/evaluator

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
