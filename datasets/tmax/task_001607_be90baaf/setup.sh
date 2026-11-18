#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest numpy scipy

    mkdir -p /app
    cat << 'EOF' > /app/gcn_propagate.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <cmath>
#include <iomanip>
#include <algorithm>

using namespace std;

int main(int argc, char** argv) {
    if(argc != 3) return 1;
    ifstream fedges(argv[1]);
    ifstream ffeat(argv[2]);

    map<int, vector<int>> adj;
    map<int, double> feat;
    string line, a, b;

    while(getline(fedges, line)) {
        if(line.empty() || line.find("source") != string::npos) continue;
        stringstream ss(line);
        getline(ss, a, ',');
        getline(ss, b, ',');
        int u = stoi(a);
        int v = stoi(b);
        adj[u].push_back(v);
        adj[v].push_back(u);
    }

    while(getline(ffeat, line)) {
        if(line.empty() || line.find("node_id") != string::npos) continue;
        stringstream ss(line);
        getline(ss, a, ',');
        getline(ss, b, ',');
        feat[stoi(a)] = stod(b);
    }

    map<int, double> deg;
    for(auto const& [u, f] : feat) {
        adj[u].push_back(u); // self loop
        deg[u] = adj[u].size();
    }

    map<int, double> out;
    for(auto const& [u, f] : feat) {
        double sum = 0;
        for(int v : adj[u]) {
            sum += feat[v] / sqrt(deg[u] * deg[v]);
        }
        out[u] = sum;
    }

    for(auto const& [u, val] : out) {
        cout << u << "," << fixed << setprecision(6) << val << "\n";
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 -o /app/gcn_propagate /app/gcn_propagate.cpp
    strip /app/gcn_propagate
    rm /app/gcn_propagate.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
