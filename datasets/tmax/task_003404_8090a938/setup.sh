#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak g++
    pip3 install pytest

    mkdir -p /app
    # Generate audio
    espeak -w /app/lab_notes.wav "Warning. Please exclude node twelve, node forty five, and node eighty eight from the citation graph."

    # Generate random graph
    python3 -c '
import random
random.seed(42)
with open("/app/citations.txt", "w") as f:
    for _ in range(500):
        u = random.randint(0, 99)
        v = random.randint(0, 99)
        w = random.randint(1, 20)
        if u != v:
            f.write(f"{u} {v} {w}\n")
'

    # Create oracle C++ program
    cat << 'EOF' > /app/oracle_pathfinder.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <fstream>
#include <unordered_map>
#include <unordered_set>

using namespace std;

const int INF = 1e9;

int main() {
    unordered_map<int, vector<pair<int, int>>> adj;
    ifstream fin("/app/citations.txt");
    int u, v, w;
    while (fin >> u >> v >> w) {
        adj[u].push_back({v, w});
    }

    unordered_set<int> bad = {12, 45, 88};

    int start, end;
    while (cin >> start >> end) {
        if (bad.count(start) || bad.count(end)) {
            cout << -1 << "\n";
            continue;
        }

        unordered_map<int, int> dist;
        priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;

        dist[start] = 0;
        pq.push({0, start});

        bool found = false;
        while (!pq.empty()) {
            auto [d, curr] = pq.top();
            pq.pop();

            if (curr == end) {
                cout << d << "\n";
                found = true;
                break;
            }

            if (d > dist[curr]) continue;

            for (auto& edge : adj[curr]) {
                int next = edge.first;
                int weight = edge.second;

                if (bad.count(next)) continue;

                if (dist.find(next) == dist.end() || dist[curr] + weight < dist[next]) {
                    dist[next] = dist[curr] + weight;
                    pq.push({dist[next], next});
                }
            }
        }
        if (!found) cout << -1 << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle_pathfinder.cpp -o /app/oracle_pathfinder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
