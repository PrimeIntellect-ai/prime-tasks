#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy scipy networkx pandas

    mkdir -p /app

    cat << 'EOF' > /tmp/sim.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <random>
#include <string>
#include <sstream>
#include <algorithm>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <input_graph.txt> <output_signal.csv>\n";
        return 1;
    }
    string in_file = argv[1];
    string out_file = argv[2];

    ifstream fin(in_file);
    if (!fin.is_open()) return 1;

    int u, v;
    int n = 0;
    vector<pair<int, int>> edges;
    while (fin >> u >> v) {
        edges.push_back({u, v});
        n = max(n, max(u, v));
    }
    n++;

    vector<vector<double>> L(n, vector<double>(n, 0.0));
    for (auto e : edges) {
        int i = e.first, j = e.second;
        L[i][i] += 1.0;
        L[j][j] += 1.0;
        L[i][j] -= 1.0;
        L[j][i] -= 1.0;
    }

    double dt = 0.01;
    int steps = 1000;
    double omega = 3.14159265;
    double sigma = 5.0;

    vector<double> x(n, 0.0);
    vector<double> x0_history;

    random_device rd;
    mt19937 gen(rd());
    normal_distribution<double> d(0.0, 1.0);

    for (int step = 0; step < steps; step++) {
        double t = step * dt;
        vector<double> drift(n, 0.0);
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                drift[i] -= L[i][j] * x[j];
            }
        }
        drift[0] += sin(omega * t);

        vector<double> next_x = x;
        for (int i = 0; i < n; i++) {
            next_x[i] += drift[i] * dt + sigma * sqrt(dt) * d(gen);
        }
        x = next_x;
        x0_history.push_back(x[0]);
    }

    ofstream fout(out_file);
    for (double val : x0_history) {
        fout << val << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /tmp/sim.cpp -o /app/simulate_network
    strip /app/simulate_network
    rm /tmp/sim.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
