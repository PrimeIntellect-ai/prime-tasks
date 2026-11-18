#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the oracle C++ source
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <unordered_map>

using namespace std;

int main() {
    int T;
    if (!(cin >> T)) return 0;
    unordered_map<int, vector<int>> adj;
    for (int i = 0; i < T; ++i) {
        int u, v, w;
        cin >> u >> v >> w;
        if (w >= 8500) {
            adj[u].push_back(v);
        }
    }
    int Q;
    if (!(cin >> Q)) return 0;
    for (int i = 0; i < Q; ++i) {
        int start, end;
        cin >> start >> end;
        if (start == end) {
            cout << 0 << "\n";
            continue;
        }
        unordered_map<int, int> dist;
        queue<int> q;
        q.push(start);
        dist[start] = 0;
        int ans = -1;
        while (!q.empty()) {
            int curr = q.front();
            q.pop();
            if (curr == end) {
                ans = dist[curr];
                break;
            }
            if (dist[curr] >= 4) continue;
            for (int nxt : adj[curr]) {
                if (dist.find(nxt) == dist.end()) {
                    dist[nxt] = dist[curr] + 1;
                    q.push(nxt);
                }
            }
        }
        if (ans > 4) ans = -1;
        cout << ans << "\n";
    }
    return 0;
}
EOF

    # Compile the oracle
    g++ -O3 -o /app/oracle /app/oracle.cpp
    rm /app/oracle.cpp

    # Generate the compliance rules image
    cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "STRICT COMPLIANCE RULES AUDIT 2024\nMIN_AMOUNT=8500\nMAX_HOPS=4\n"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/compliance_rules.png')
EOF

    python3 /app/generate_image.py
    rm /app/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
