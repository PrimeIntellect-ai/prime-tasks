#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <string>
#include <unordered_set>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    int V, E;
    if (!(cin >> V >> E)) return 0;

    vector<unordered_set<int>> adj(V);
    vector<unordered_set<int>> rev_adj(V);

    for (int i = 0; i < E; ++i) {
        int u, v;
        cin >> u >> v;
        if (u >= 0 && u < V && v >= 0 && v < V) {
            adj[u].insert(v);
            rev_adj[v].insert(u);
        }
    }

    int Q;
    if (!(cin >> Q)) return 0;

    for (int i = 0; i < Q; ++i) {
        string type;
        cin >> type;
        if (type == "CENTRALITY") {
            int u;
            cin >> u;
            if (u >= 0 && u < V) {
                long long in_deg = rev_adj[u].size();
                long long out_deg = adj[u].size();
                cout << in_deg * out_deg << "\n";
            } else {
                cout << 0 << "\n";
            }
        } else if (type == "CO_CITE") {
            int u, v;
            cin >> u >> v;
            if (u >= 0 && u < V && v >= 0 && v < V) {
                int count = 0;
                for (int w : adj[u]) {
                    if (adj[v].count(w)) {
                        count++;
                    }
                }
                cout << count << "\n";
            } else {
                cout << 0 << "\n";
            }
        } else if (type == "PATTERN") {
            int u;
            cin >> u;
            if (u >= 0 && u < V) {
                int count = 0;
                for (int v : rev_adj[u]) {
                    for (int w : adj[u]) {
                        if (adj[v].count(w)) {
                            count++;
                        }
                    }
                }
                cout << count << "\n";
            } else {
                cout << 0 << "\n";
            }
        }
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle.cpp -o /app/dataset_analyzer
    strip /app/dataset_analyzer
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
