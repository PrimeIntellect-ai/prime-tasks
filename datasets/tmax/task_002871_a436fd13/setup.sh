#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest pandas

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <set>
#include <algorithm>

using namespace std;

void dfs(int u, map<int, vector<int>>& adj, set<int>& visited, vector<int>& comp) {
    visited.insert(u);
    comp.push_back(u);
    for (int v : adj[u]) {
        if (visited.find(v) == visited.end()) {
            dfs(v, adj, visited, comp);
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    ifstream in(argv[1]);
    ofstream out(argv[2]);

    string line;
    getline(in, line); // skip header

    map<int, vector<int>> adj;
    set<int> nodes;

    while (getline(in, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string s1, s2;
        getline(ss, s1, ',');
        getline(ss, s2, ',');
        int u = stoi(s1);
        int v = stoi(s2);
        adj[u].push_back(v);
        adj[v].push_back(u);
        nodes.insert(u);
        nodes.insert(v);
    }

    set<int> visited;
    map<int, int> comp_id;
    map<int, int> degree;
    map<int, int> rank_map;

    for (int u : nodes) {
        degree[u] = adj[u].size();
        if (visited.find(u) == visited.end()) {
            vector<int> comp;
            dfs(u, adj, visited, comp);
            int min_id = *min_element(comp.begin(), comp.end());

            set<int, greater<int>> unique_degrees;
            for (int v : comp) {
                comp_id[v] = min_id;
                unique_degrees.insert(degree[v]);
            }
            map<int, int> deg_to_rank;
            int r = 1;
            for (int d : unique_degrees) {
                deg_to_rank[d] = r++;
            }
            for (int v : comp) {
                rank_map[v] = deg_to_rank[degree[v]];
            }
        }
    }

    out << "node,component_id,degree,rank\n";
    for (int u : nodes) {
        out << u << "," << comp_id[u] << "," << degree[u] << "," << rank_map[u] << "\n";
    }

    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/graph_oracle
    strip /app/graph_oracle
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
