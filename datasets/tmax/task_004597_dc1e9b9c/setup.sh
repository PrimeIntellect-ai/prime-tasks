#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/data /app/audio /app/oracle

    # Generate known_edges.csv
    echo "source_id,target_id,latency" > /app/data/known_edges.csv
    echo "1,10,20" >> /app/data/known_edges.csv
    echo "10,25,5" >> /app/data/known_edges.csv
    echo "25,199,100" >> /app/data/known_edges.csv
    echo "1,50,30" >> /app/data/known_edges.csv

    # Generate synthetic audio using espeak
    espeak -w /app/audio/network_intel.wav "Update to the routing table. Node fifty connects to node one twenty with a latency of fifteen. Node one twenty connects to node one ninety nine with a latency of eight. Node ten connects to node fifty with a latency of four."

    # Create oracle C++ source
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <map>

using namespace std;

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    int src = stoi(argv[1]);
    int dst = stoi(argv[2]);

    map<int, vector<pair<int, int>>> adj;
    adj[1].push_back({10, 20});
    adj[10].push_back({25, 5});
    adj[25].push_back({199, 100});
    adj[1].push_back({50, 30});
    adj[50].push_back({120, 15});
    adj[120].push_back({199, 8});
    adj[10].push_back({50, 4});

    map<int, int> dist;
    priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;

    pq.push({0, src});
    dist[src] = 0;

    while (!pq.empty()) {
        auto p = pq.top();
        int d = p.first;
        int u = p.second;
        pq.pop();

        if (d > dist[u]) continue;
        if (u == dst) break;

        for (auto& edge : adj[u]) {
            int v = edge.first;
            int weight = edge.second;
            if (dist.find(v) == dist.end() || dist[u] + weight < dist[v]) {
                dist[v] = dist[u] + weight;
                pq.push({dist[v], v});
            }
        }
    }

    if (dist.find(dst) != dist.end()) {
        cout << dist[dst] << endl;
    } else {
        cout << -1 << endl;
    }

    return 0;
}
EOF

    # Compile the oracle
    g++ -O3 /tmp/oracle.cpp -o /app/oracle/reference_engine
    chmod +x /app/oracle/reference_engine
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
