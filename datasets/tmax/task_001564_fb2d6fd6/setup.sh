#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate the image with the rules
    cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (600, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "ETL Filtering Rules:\n1. Exclude edges where wait_time_ms < 15.\n2. Exclude src_tx starting with 'SYS_'.\n3. Exclude tx_type equal to 'MAINT'."
d.text((10,10), text, fill=(0,0,0))
img.save('/app/graph_rules.png')
EOF
    python3 /app/generate_image.py

    # Generate the CSV dataset
    cat << 'EOF' > /app/generate_data.py
import random
random.seed(42)
with open('/app/transactions.csv', 'w') as f:
    f.write('src_tx,dst_tx,wait_time_ms,tx_type\n')
    for i in range(150000):
        src = f"TX_{random.randint(1, 50000)}"
        dst = f"TX_{random.randint(1, 50000)}"
        wait = random.randint(5, 50)
        tx_type = random.choice(['READ', 'WRITE', 'MAINT'])
        if random.random() < 0.05:
            src = f"SYS_{random.randint(1, 1000)}"
        f.write(f"{src},{dst},{wait},{tx_type}\n")
    # Add planted cycles
    for i in range(10):
        nodes = [f"TX_{random.randint(1, 50000)}" for _ in range(5)]
        for j in range(5):
            src = nodes[j]
            dst = nodes[(j+1)%5]
            f.write(f"{src},{dst},20,READ\n")
EOF
    python3 /app/generate_data.py

    # Write the naive C++ implementation
    cat << 'EOF' > /app/naive.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>

using namespace std;

bool dfs(const string& u, unordered_map<string, vector<string>>& adj, unordered_set<string>& visited, unordered_set<string>& recStack, unordered_set<string>& cycleNodes, vector<string>& path) {
    visited.insert(u);
    recStack.insert(u);
    path.push_back(u);

    for (const string& v : adj[u]) {
        if (recStack.count(v)) {
            auto it = find(path.begin(), path.end(), v);
            for (; it != path.end(); ++it) {
                cycleNodes.insert(*it);
            }
        } else if (!visited.count(v)) {
            dfs(v, adj, visited, recStack, cycleNodes, path);
        }
    }

    recStack.erase(u);
    path.pop_back();
    return false;
}

int main() {
    ifstream file("/app/transactions.csv");
    string line;
    getline(file, line);
    unordered_map<string, vector<string>> adj;
    vector<string> all_nodes;

    while (getline(file, line)) {
        stringstream ss(line);
        string src, dst, wait_str, type;
        getline(ss, src, ',');
        getline(ss, dst, ',');
        getline(ss, wait_str, ',');
        getline(ss, type, ',');

        int wait = stoi(wait_str);
        if (wait < 15) continue;
        if (src.substr(0, 4) == "SYS_") continue;
        if (type == "MAINT") continue;

        adj[src].push_back(dst);
        all_nodes.push_back(src);
        all_nodes.push_back(dst);
    }

    unordered_set<string> unique_nodes(all_nodes.begin(), all_nodes.end());
    unordered_set<string> cycleNodes;

    for (const string& start_node : unique_nodes) {
        unordered_set<string> visited;
        unordered_set<string> recStack;
        vector<string> path;
        dfs(start_node, adj, visited, recStack, cycleNodes, path);
    }

    vector<string> result(cycleNodes.begin(), cycleNodes.end());
    sort(result.begin(), result.end());

    ofstream out("/home/user/deadlocks.txt");
    for (const string& node : result) {
        out << node << "\n";
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
