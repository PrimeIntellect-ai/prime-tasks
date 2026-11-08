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
#include <limits>

using namespace std;

const int INF = numeric_limits<int>::max();

int main() {
    int N, M;
    if (!(cin >> N >> M)) return 0;

    vector<vector<pair<int, int>>> adj(N);
    vector<long long> out_weight(N, 0);

    for (int i = 0; i < M; ++i) {
        int u, v, w;
        cin >> u >> v >> w;
        adj[u].push_back({v, w});
        out_weight[u] += w;
    }

    int Q;
    cin >> Q;
    while (Q--) {
        int type;
        cin >> type;
        if (type == 0) {
            int u;
            cin >> u;
            cout << out_weight[u] << "\n";
        } else if (type == 1) {
            int u, v;
            cin >> u >> v;
            vector<int> dist(N, INF);
            priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;

            dist[u] = 0;
            pq.push({0, u});

            while (!pq.empty()) {
                auto [d, curr] = pq.top();
                pq.pop();

                if (d > dist[curr]) continue;
                if (curr == v) break;

                for (auto& edge : adj[curr]) {
                    int next = edge.first;
                    int weight = edge.second;

                    if (dist[curr] + weight < dist[next]) {
                        dist[next] = dist[curr] + weight;
                        pq.push({dist[next], next});
                    }
                }
            }
            if (dist[v] == INF) cout << "-1\n";
            else cout << dist[v] << "\n";
        }
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle.cpp -o /app/backup_route_calc
    strip /app/backup_route_calc
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
