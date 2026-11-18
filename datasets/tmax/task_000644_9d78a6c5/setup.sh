#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk coreutils sed grep
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the C++ evaluator
    cat << 'EOF' > /tmp/evaluator.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cmath>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    ifstream file(argv[1]);
    if (!file.is_open()) {
        cerr << "Could not open file" << endl;
        return 1;
    }
    string line;
    vector<vector<double>> X;
    vector<int> y;
    getline(file, line); // skip header
    while (getline(file, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string val;
        vector<double> row;
        while (getline(ss, val, ',')) {
            try {
                row.push_back(stod(val));
            } catch (...) {
                row.push_back(0.0);
            }
        }
        if (row.empty()) continue;
        y.push_back(row.back());
        row.pop_back();
        row.insert(row.begin(), 1.0); // bias
        X.push_back(row);
    }

    int n = X.size();
    if (n == 0) return 0;
    int d = X[0].size();
    vector<double> w(d, 0.0);
    double lr = 0.1;
    for (int iter = 0; iter < 500; ++iter) {
        vector<double> grad(d, 0.0);
        for (int i = 0; i < n; ++i) {
            double z = 0;
            for (int j = 0; j < d; ++j) z += w[j] * X[i][j];
            double p = 1.0 / (1.0 + exp(-z));
            double err = p - y[i];
            for (int j = 0; j < d; ++j) grad[j] += err * X[i][j];
        }
        for (int j = 0; j < d; ++j) w[j] -= lr * grad[j] / n;
    }

    int correct = 0;
    for (int i = 0; i < n; ++i) {
        double z = 0;
        for (int j = 0; j < d; ++j) z += w[j] * X[i][j];
        int pred = z > 0 ? 1 : 0;
        if (pred == y[i]) correct++;
    }
    double acc = (double)correct / n;
    cout << "EVALUATION COMPLETED. ACCURACY=" << acc << endl;
    return 0;
}
EOF

    g++ -O3 -o /app/model_evaluator /tmp/evaluator.cpp
    strip /app/model_evaluator
    chmod +x /app/model_evaluator
    rm /tmp/evaluator.cpp

    # Generate raw_data.csv
    cat << 'EOF' > /tmp/generate_data.py
import random
import csv

random.seed(42)

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow([f'f{i}' for i in range(1, 11)] + ['target'])
    for _ in range(1000):
        target = random.choice([0, 1])
        # f1, f3, f4, f7, f9 correlated
        f1 = target * 2.0 + random.gauss(0, 1)
        f3 = target * -1.5 + random.gauss(0, 1)
        f4 = target * 3.0 + random.gauss(0, 1)
        f7 = target * 0.8 + random.gauss(0, 1)
        f9 = target * -2.5 + random.gauss(0, 1)
        # f2, f5, f6, f8, f10 random noise
        f2 = random.gauss(0, 1)
        f5 = random.gauss(0, 1)
        f6 = random.gauss(0, 1)
        f8 = random.gauss(0, 1)
        f10 = random.gauss(0, 1)

        row = [f"{x:.4f}" for x in [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10]] + [target]

        if random.random() < 0.05:
            idx = random.randint(0, 9)
            row[idx] = '?'

        writer.writerow(row)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
