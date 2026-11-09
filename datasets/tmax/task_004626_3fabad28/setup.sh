#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <unordered_map>
#include <vector>
#include <string>

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    std::ifstream infile(argv[1]);
    int target = std::stoi(argv[2]);

    std::unordered_map<int, std::vector<int>> reverse_adj;
    int u, v;
    while (infile >> u >> v) {
        reverse_adj[v].push_back(u);
    }

    long long score = 0;
    // 1-hop
    score += 5 * reverse_adj[target].size();

    // 2-hop
    for (int pred : reverse_adj[target]) {
        score += 2 * reverse_adj[pred].size();
    }

    std::cout << score << std::endl;
    return 0;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/graph_oracle.bin
    strip /app/graph_oracle.bin
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
