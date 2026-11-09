#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak-ng
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak-ng -w /app/network.wav "ten twenty. ten thirty. twenty forty. twenty fifty. thirty sixty. thirty seventy. forty eighty. forty ninety. fifty one hundred. fifty one hundred ten."

    # Create the oracle source code
    cat << 'EOF' > /app/oracle_query.cpp
#include <iostream>
#include <vector>
#include <unordered_map>
#include <queue>

using namespace std;

unordered_map<int, vector<int>> adj = {
    {10, {20, 30}}, {20, {10, 40, 50}}, {30, {10, 60, 70}},
    {40, {20, 80, 90}}, {50, {20, 100, 110}}, {60, {30}},
    {70, {30}}, {80, {40}}, {90, {40}}, {100, {50}}, {110, {50}}
};

int bfs(int u, int v) {
    if (u == v) return 0;
    if (adj.find(u) == adj.end() || adj.find(v) == adj.end()) return -1;
    unordered_map<int, int> dist;
    queue<int> q;
    q.push(u);
    dist[u] = 0;
    while (!q.empty()) {
        int curr = q.front();
        q.pop();
        if (curr == v) return dist[curr];
        for (int nxt : adj[curr]) {
            if (dist.find(nxt) == dist.end()) {
                dist[nxt] = dist[curr] + 1;
                q.push(nxt);
            }
        }
    }
    return -1;
}

int main(int argc, char** argv) {
    int u, v;
    while (cin >> u >> v) {
        cout << bfs(u, v) << "\n";
    }
    return 0;
}
EOF

    # Compile the oracle
    g++ -O3 -o /app/oracle_query /app/oracle_query.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
