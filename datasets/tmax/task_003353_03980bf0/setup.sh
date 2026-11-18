#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ strace ltrace binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/cluster_verifier.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <vector>
#include <algorithm>
#include <set>

using namespace std;

struct UnionFind {
    map<int, int> parent;

    void add(int i) {
        if (parent.find(i) == parent.end()) {
            parent[i] = i;
        }
    }

    int find(int i) {
        if (parent[i] == i)
            return i;
        return parent[i] = find(parent[i]);
    }

    void unite(int i, int j) {
        int root_i = find(i);
        int root_j = find(j);
        if (root_i != root_j) {
            parent[root_i] = root_j;
        }
    }
};

int main(int argc, char* argv[]) {
    string in_file = "";
    string out_file = "";

    for (int i = 1; i < argc; i++) {
        string arg = argv[i];
        if (arg == "--in" && i + 1 < argc) {
            in_file = argv[++i];
        } else if (arg == "--out" && i + 1 < argc) {
            out_file = argv[++i];
        }
    }

    if (in_file == "" || out_file == "") return 1;

    ifstream infile(in_file);
    string line;
    UnionFind uf;
    set<int> all_nodes;

    while (getline(infile, line)) {
        if(line.empty()) continue;
        stringstream ss(line);
        string src_str, tgt_str;
        if (getline(ss, src_str, ',') && getline(ss, tgt_str, ',')) {
            try {
                int src = stoi(src_str);
                int tgt = stoi(tgt_str);
                uf.add(src);
                uf.add(tgt);
                uf.unite(src, tgt);
                all_nodes.insert(src);
                all_nodes.insert(tgt);
            } catch (...) {
                // Ignore invalid lines
            }
        }
    }

    map<int, int> comp_min;
    for (int node : all_nodes) {
        int root = uf.find(node);
        if (comp_min.find(root) == comp_min.end()) {
            comp_min[root] = node;
        } else {
            comp_min[root] = min(comp_min[root], node);
        }
    }

    ofstream outfile(out_file);
    outfile << "{\n";
    bool first = true;
    for (int node : all_nodes) {
        if (!first) outfile << ",\n";
        outfile << "  \"" << node << "\": " << comp_min[uf.find(node)];
        first = false;
    }
    outfile << "\n}\n";

    return 0;
}
EOF

    g++ -O3 /app/cluster_verifier.cpp -o /app/cluster_verifier
    strip /app/cluster_verifier
    chmod +x /app/cluster_verifier
    rm /app/cluster_verifier.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
