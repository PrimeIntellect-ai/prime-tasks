#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <algorithm>

using namespace std;

int main() {
    int n, m, s, t;
    if (!(cin >> n >> m >> s >> t)) return 0;
    vector<vector<pair<int, int>>> adj(n);
    for (int i = 0; i < m; ++i) {
        int u, v, w;
        cin >> u >> v >> w;
        adj[u].push_back({v, w});
    }
    vector<int> max_weight(n, -1);
    priority_queue<pair<int, int>> pq;
    max_weight[s] = 2e9; // infinity
    pq.push({2e9, s});

    while (!pq.empty()) {
        int w = pq.top().first;
        int u = pq.top().second;
        pq.pop();

        if (w < max_weight[u]) continue;
        if (u == t) break;

        for (auto edge : adj[u]) {
            int v = edge.first;
            int weight = edge.second;
            int min_w = min(w, weight);
            if (min_w > max_weight[v]) {
                max_weight[v] = min_w;
                pq.push({min_w, v});
            }
        }
    }

    if (max_weight[t] == 2e9 || max_weight[t] == -1) cout << -1 << endl;
    else cout << max_weight[t] << endl;

    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/deadlock_oracle
    strip /app/deadlock_oracle
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
