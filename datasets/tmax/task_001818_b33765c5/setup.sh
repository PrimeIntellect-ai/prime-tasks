#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 g++
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <unordered_map>
#include <queue>
#include <cstdlib>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    ifstream fin(argv[1]);
    int source = atoi(argv[2]);
    int target = atoi(argv[3]);

    if (source == target) {
        cout << 0 << "\n";
        return 0;
    }

    unordered_map<int, vector<int>> adj;
    int u, v;
    while (fin >> u >> v) {
        adj[u].push_back(v);
    }

    unordered_map<int, int> dist;
    queue<int> q;
    q.push(source);
    dist[source] = 0;

    while (!q.empty()) {
        int curr = q.front();
        q.pop();

        if (curr == target) {
            cout << dist[curr] << "\n";
            return 0;
        }

        for (int nxt : adj[curr]) {
            if (dist.find(nxt) == dist.end()) {
                dist[nxt] = dist[curr] + 1;
                q.push(nxt);
            }
        }
    }

    cout << -1 << "\n";
    return 0;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/citation_oracle
    strip /app/citation_oracle
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
