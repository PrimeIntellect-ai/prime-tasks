#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    mkdir -p /app

    # Generate synthetic data
    cat << 'EOF' > /app/gen_data.py
import numpy as np
import pandas as pd
np.random.seed(42)
x = np.linspace(0, 10, 100)
a_true, b_true = 3.5, 1.2
y = a_true * np.exp(-b_true * x) + np.random.normal(0, 0.5, 100)
pd.DataFrame({'x': x, 'y': y}).to_csv('/app/data.csv', index=False, header=False)
EOF
    python3 /app/gen_data.py

    # Create oracle source code
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <random>
#include <string>
#include <sstream>

using namespace std;

struct DataPoint {
    double x, y;
};

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    string in_file = argv[1];
    string out_file = argv[2];

    vector<DataPoint> data;
    ifstream fin(in_file);
    string line;
    while (getline(fin, line)) {
        stringstream ss(line);
        string sx, sy;
        if (getline(ss, sx, ',') && getline(ss, sy, ',')) {
            data.push_back({stod(sx), stod(sy)});
        }
    }

    double a = 5.0, b = 2.5;
    double sigma = 0.5;

    auto log_likelihood = [&](double a, double b) {
        double ll = 0;
        for (auto& p : data) {
            double pred = a * exp(-b * p.x);
            double diff = p.y - pred;
            ll += -0.5 * (diff * diff) / (sigma * sigma);
        }
        return ll;
    };

    mt19937 gen(42);
    normal_distribution<double> prop(0.0, 0.1);
    uniform_real_distribution<double> unif(0.0, 1.0);

    double current_ll = log_likelihood(a, b);

    ofstream fout(out_file);
    for (int i = 0; i < 100000; i++) {
        // artificial delay to make it slow enough to measure speedup
        for(volatile int j=0; j<20000; j++) {}

        double a_prop = a + prop(gen);
        double b_prop = b + prop(gen);

        if (a_prop < 0 || a_prop > 10 || b_prop < 0 || b_prop > 5) {
            fout << a << "," << b << "\n";
            continue;
        }

        double prop_ll = log_likelihood(a_prop, b_prop);
        if (log(unif(gen)) < prop_ll - current_ll) {
            a = a_prop;
            b = b_prop;
            current_ll = prop_ll;
        }
        fout << a << "," << b << "\n";
    }
    return 0;
}
EOF

    # Compile stripped binary
    g++ -O3 /app/oracle.cpp -o /app/oracle_mcmc -s
    rm /app/oracle.cpp /app/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
