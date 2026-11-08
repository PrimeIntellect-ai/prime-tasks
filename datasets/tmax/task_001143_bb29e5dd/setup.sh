#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/extract.cpp
#include <iostream>
#include <fstream>
#include <vector>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    ifstream fin(argv[1]);
    int num_nodes;
    fin >> num_nodes;
    vector<vector<int>> adj(num_nodes);
    vector<int> deg(num_nodes, 0);
    int u, v;
    while (fin >> u >> v) {
        adj[u].push_back(v);
        deg[u]++;
    }

    for (int i = 0; i < num_nodes; ++i) {
        double sum = 0;
        for (int neighbor : adj[i]) {
            sum += deg[neighbor];
        }
        // BUG: division by zero if deg[i] == 0
        double mean_neigh_deg = sum / deg[i];
        cout << i << " " << mean_neigh_deg << "\n";
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/graph.txt
10
0 1
1 0
1 2
2 1
3 4
4 3
4 5
5 4
6 7
7 6
EOF

chmod -R 777 /home/user
