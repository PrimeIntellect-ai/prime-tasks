#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        python3-opencv \
        tesseract-ocr \
        libtesseract-dev \
        ffmpeg

    pip3 install pytest numpy opencv-python-headless pytesseract

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the video
    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

frames = [
    {"time": 0, "text": "T 1 BACKUP"},
    {"time": 1, "text": "T 2 USER"},
    {"time": 2, "text": "T 3 USER"},
    {"time": 3, "text": "W 2 1"},
    {"time": 4, "text": "W 3 2"},
    {"time": 5, "text": "W 1 3"},
    {"time": 6, "text": "T 4 BACKUP"},
    {"time": 7, "text": "W 4 3"},
    {"time": 8, "text": "T 5 USER"},
    {"time": 9, "text": "W 5 4"},
    {"time": 10, "text": "W 2 4"},
    {"time": 11, "text": "W 4 2"},
    {"time": 12, "text": "R 5 4"},
    {"time": 13, "text": "T 6 BACKUP"},
    {"time": 14, "text": "W 6 6"}
]

out = cv2.VideoWriter('/app/dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (640, 480))
for f in frames:
    img = np.ones((480, 640, 3), dtype=np.uint8) * 255
    text = f["text"]
    font = cv2.FONT_HERSHEY_SIMPLEX
    # Simple centering approximation
    cv2.putText(img, text, (150, 240), font, 1.5, (0, 0, 0), 3, cv2.LINE_AA)
    out.write(img)
out.release()
EOF
    python3 /tmp/make_video.py

    # Build the oracle
    cat << 'EOF' > /opt/oracle/resolve_deadlocks_oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <sstream>

using namespace std;

enum Type { USER, BACKUP };

struct Txn {
    int id;
    Type type;
};

unordered_map<int, Txn> txns;
unordered_map<int, unordered_set<int>> adj;

bool dfs(int u, unordered_map<int, int>& color, vector<int>& path, vector<int>& cycle) {
    color[u] = 1;
    path.push_back(u);
    for (int v : adj[u]) {
        if (color[v] == 0) {
            if (dfs(v, color, path, cycle)) return true;
        } else if (color[v] == 1) {
            auto it = find(path.begin(), path.end(), v);
            cycle.assign(it, path.end());
            return true;
        }
    }
    color[u] = 2;
    path.pop_back();
    return false;
}

void remove_txn(int id) {
    adj.erase(id);
    for (auto& p : adj) {
        p.second.erase(id);
    }
    txns.erase(id);
}

void check_deadlock() {
    unordered_map<int, int> color;
    for (auto& p : txns) color[p.first] = 0;

    vector<int> nodes;
    for (auto& p : txns) nodes.push_back(p.first);
    sort(nodes.begin(), nodes.end());

    vector<int> cycle;
    bool found = false;
    for (int u : nodes) {
        if (color[u] == 0) {
            vector<int> path;
            if (dfs(u, color, path, cycle)) {
                found = true;
                break;
            }
        }
    }

    if (!found) return;

    vector<int> sorted_cycle = cycle;
    sort(sorted_cycle.begin(), sorted_cycle.end());
    cout << "DEADLOCK DETECTED:";
    for (int u : sorted_cycle) cout << " " << u;
    cout << "\n";

    int victim = -1;
    for (int u : cycle) {
        if (victim == -1) {
            victim = u;
            continue;
        }

        bool u_is_user = (txns[u].type == USER);
        bool v_is_user = (txns[victim].type == USER);

        if (u_is_user && !v_is_user) {
            victim = u;
        } else if (u_is_user == v_is_user) {
            int u_out = adj[u].size();
            int v_out = adj[victim].size();
            if (u_out > v_out) {
                victim = u;
            } else if (u_out == v_out) {
                if (u > victim) {
                    victim = u;
                }
            }
        }
    }

    cout << "ABORT: " << victim << "\n";
    remove_txn(victim);
}

int main() {
    string line;
    while (getline(cin, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string cmd;
        ss >> cmd;
        if (cmd == "T") {
            int id;
            string type_str;
            ss >> id >> type_str;
            if (type_str == "USER") txns[id] = {id, USER};
            else if (type_str == "BACKUP") txns[id] = {id, BACKUP};
        } else if (cmd == "W") {
            int u, v;
            ss >> u >> v;
            if (txns.count(u) && txns.count(v)) {
                adj[u].insert(v);
                check_deadlock();
            }
        } else if (cmd == "R") {
            int u, v;
            ss >> u >> v;
            if (txns.count(u) && txns.count(v)) {
                adj[u].erase(v);
            }
        }
    }
    return 0;
}
EOF
    g++ -O3 /opt/oracle/resolve_deadlocks_oracle.cpp -o /opt/oracle/resolve_deadlocks_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
