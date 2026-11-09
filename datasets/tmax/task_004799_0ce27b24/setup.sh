#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make file
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/deps.txt
A B
A C
C D
B D
D E
E F
B F
EOF

    cat << 'EOF' > /tmp/legacy.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <vector>
#include <unordered_set>
#include <algorithm>

using namespace std;

unordered_map<string, vector<string>> adj;
unordered_set<string> visiting;
unordered_set<string> visited;

int max_len = 0;

bool has_cycle(const string& u) {
    visiting.insert(u);
    for (const string& v : adj[u]) {
        if (visiting.count(v)) return true;
        if (!visited.count(v) && has_cycle(v)) return true;
    }
    visiting.erase(u);
    visited.insert(u);
    return false;
}

void dfs(const string& u, int depth) {
    max_len = max(max_len, depth);
    for (const string& v : adj[u]) {
        dfs(v, depth + 1);
    }
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <deps.txt>\n";
        return 1;
    }
    ifstream fin(argv[1]);
    if (!fin) {
        cerr << "Could not open file\n";
        return 1;
    }
    string u, v;
    while (fin >> u >> v) {
        adj[u].push_back(v);
        if (adj.find(v) == adj.end()) adj[v] = {};
    }

    for (auto& pair : adj) {
        if (!visited.count(pair.first)) {
            if (has_cycle(pair.first)) {
                cout << "CYCLE\n";
                return 1;
            }
        }
    }

    for (auto& pair : adj) {
        dfs(pair.first, 0);
    }

    cout << max_len << "\n";
    return 0;
}
EOF

    g++ -O3 /tmp/legacy.cpp -o /app/legacy_resolver
    strip -s /app/legacy_resolver
    rm /tmp/legacy.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
