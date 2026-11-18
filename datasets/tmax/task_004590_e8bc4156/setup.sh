#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/dataset.txt
1000000.1
1000000.2
1000000.3
1000000.4
1000000.5
EOF

    cat << 'EOF' > /home/user/project/spectral_analyzer.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>

using namespace std;

// Buggy function: Naive variance
double calculate_variance(const vector<double>& data, double& mean) {
    double sum = 0.0;
    double sum_sq = 0.0;
    int n = data.size();

    for (double x : data) {
        sum += x;
        sum_sq += x * x;
    }

    mean = sum / n;
    // This will cause catastrophic cancellation for large values close together
    return (sum_sq / n) - (mean * mean); 
}

// Nonlinear equation solver finding root of f(x) = var * x^2 - mean * x + 1000 = 0
// using quadratic formula (simplified for this task)
double solve_calibration(double mean, double variance) {
    if (variance < 0) {
        return NAN; // Instability leads here
    }
    // simple dummy nonlinear calculation
    return std::sqrt(variance) + (mean / 1000000.0);
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <dataset>" << endl;
        return 1;
    }

    ifstream infile(argv[1]);
    vector<double> data;
    double val;
    while (infile >> val) {
        data.push_back(val);
    }

    double mean = 0.0;
    double variance = calculate_variance(data, mean);
    double coeff = solve_calibration(mean, variance);

    cout << fixed << setprecision(4);
    cout << "Mean: " << mean << endl;
    cout << "Variance: " << variance << endl;
    cout << "Calibration Coefficient: " << coeff << endl;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
