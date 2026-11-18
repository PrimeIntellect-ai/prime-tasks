#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        ffmpeg \
        tesseract-ocr \
        g++ \
        libsm6 libxext6

    pip3 install pytest

    # Create directories
    mkdir -p /app /oracle /home/user

    # Generate video with text
    # Using ffmpeg lavfi to generate a simple video with text
    ffmpeg -f lavfi -i "color=c=black:s=640x480:d=2" -vf "drawtext=text='LINK 0 1 500\nLINK 1 2 300\nLINK 2 3 400\nLINK 3 0 200':fontcolor=white:fontsize=24:x=10:y=10" -c:v libx264 -y /app/db_logs.mp4

    # Create oracle C++ source
    cat << 'EOF' > /oracle/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <algorithm>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    int N, E;
    if (!(cin >> N >> E)) return 0;
    vector<vector<pair<int, int>>> adj(N);
    for (int i = 0; i < E; ++i) {
        int u, v, w;
        cin >> u >> v >> w;
        adj[u].push_back({v, w});
        adj[v].push_back({u, w});
    }
    int Q;
    if (!(cin >> Q)) return 0;
    for (int q = 0; q < Q; ++q) {
        int src, tgt;
        cin >> src >> tgt;
        vector<int> max_b(N, -1);
        priority_queue<pair<int, int>> pq;
        pq.push({2000000000, src});
        max_b[src] = 2000000000;
        while (!pq.empty()) {
            auto [b, u] = pq.top();
            pq.pop();
            if (b < max_b[u]) continue;
            if (u == tgt) break;
            for (auto& edge : adj[u]) {
                int v = edge.first;
                int w = edge.second;
                int new_b = min(b, w);
                if (new_b > max_b[v]) {
                    max_b[v] = new_b;
                    pq.push({new_b, v});
                }
            }
        }
        if (max_b[tgt] == 2000000000 && src != tgt) {
            cout << -1 << "\n";
        } else if (max_b[tgt] == 2000000000) {
            cout << -1 << "\n"; // or whatever
        } else {
            cout << max_b[tgt] << "\n";
        }
    }
    return 0;
}
EOF

    # Compile oracle
    g++ -O3 /oracle/oracle.cpp -o /oracle/backup_router_oracle
    chmod +x /oracle/backup_router_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /oracle
