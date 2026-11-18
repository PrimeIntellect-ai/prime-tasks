#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate video
    ffmpeg -f lavfi -i "color=c=black:s=640x480:r=1:d=60" -vf "drawbox=x=0:y=0:w=640:h=480:color=white@0.8:t=fill:enable='eq(t,5)+eq(t,12)+eq(t,18)+eq(t,22)+eq(t,35)+eq(t,41)+eq(t,48)+eq(t,55)'" -c:v libx264 -y /app/signal_log.mp4

    # Generate CSV
    cat << 'EOF' > /app/network_topology.csv
timestamp_sec,source_node,target_node,latency_ms
5,0,1,10
5,1,2,15
12,2,3,5
18,0,3,40
22,3,4,10
35,4,5,20
41,1,5,50
48,0,5,100
55,2,4,25
3,0,5,1
10,1,4,2
EOF

    # Compile Oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
using namespace std;
const int INF = 1e9;
int main() {
    int n = 6;
    vector<vector<pair<int,int>>> adj(n);
    adj[0].push_back({1, 10}); adj[1].push_back({0, 10});
    adj[1].push_back({2, 15}); adj[2].push_back({1, 15});
    adj[2].push_back({3, 5}); adj[3].push_back({2, 5});
    adj[0].push_back({3, 40}); adj[3].push_back({0, 40});
    adj[3].push_back({4, 10}); adj[4].push_back({3, 10});
    adj[4].push_back({5, 20}); adj[5].push_back({4, 20});
    adj[1].push_back({5, 50}); adj[5].push_back({1, 50});
    adj[0].push_back({5, 100}); adj[5].push_back({0, 100});
    adj[2].push_back({4, 25}); adj[4].push_back({2, 25});

    int u, v;
    while(cin >> u >> v) {
        if(u >= n || v >= n) { cout << -1 << endl; continue; }
        vector<int> dist(n, INF);
        priority_queue<pair<int,int>, vector<pair<int,int>>, greater<pair<int,int>>> pq;
        dist[u] = 0; pq.push({0, u});
        while(!pq.empty()) {
            auto [d, curr] = pq.top(); pq.pop();
            if(d > dist[curr]) continue;
            for(auto& edge : adj[curr]) {
                if(dist[curr] + edge.second < dist[edge.first]) {
                    dist[edge.first] = dist[curr] + edge.second;
                    pq.push({dist[edge.first], edge.first});
                }
            }
        }
        if(dist[v] == INF) cout << -1 << "\n";
        else cout << dist[v] << "\n";
    }
    return 0;
}
EOF
    g++ -O3 /opt/oracle/oracle.cpp -o /opt/oracle/fuzz_oracle_dijkstra
    chmod +x /opt/oracle/fuzz_oracle_dijkstra

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
