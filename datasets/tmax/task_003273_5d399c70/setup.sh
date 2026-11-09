#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sequence_data.txt
0.10
0.25
0.50
0.75
EOF

    cat << 'EOF' > /home/user/divergence_solver.cpp
#include <iostream>
#include <fstream>
#include <cmath>
#include <iomanip>
#include <string>

using namespace std;

// Function to calculate f(t)
double f(double t, double p) {
    return 1.0 - exp(-0.5 * t) + 0.1 * t - p;
}

// Function to calculate f'(t)
double df(double t) {
    return 0.5 * exp(-0.5 * t) + 0.1;
}

// TODO: Implement the Newton-Raphson solver
double solve_t(double p) {
    double t = 1.0;
    // Implement here

    return t;
}

int main() {
    ifstream infile("sequence_data.txt");
    ofstream outfile("divergence_times.csv");

    if (!infile.is_open() || !outfile.is_open()) {
        cerr << "Error opening files!" << endl;
        return 1;
    }

    double p;
    outfile << fixed << setprecision(4);
    while (infile >> p) {
        double t = solve_t(p);
        outfile << p << "," << t << "\n";
    }

    infile.close();
    outfile.close();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
