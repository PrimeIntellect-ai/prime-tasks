#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/kg_matcher.cpp
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

using namespace std;

string trim(const string& str) {
    size_t first = str.find_first_not_of(" \t\r\n");
    if (string::npos == first) return "";
    size_t last = str.find_last_not_of(" \t\r\n");
    return str.substr(first, (last - first + 1));
}

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    string pred1 = argv[1];
    string pred2 = argv[2];

    vector<pair<string, string>> first_hop;
    vector<pair<string, string>> second_hop;

    string line;
    while (getline(cin, line)) {
        line = trim(line);
        if (line.empty()) continue;
        size_t p1 = line.find('|');
        if (p1 == string::npos) continue;
        size_t p2 = line.find('|', p1 + 1);
        if (p2 == string::npos) continue;

        string s = trim(line.substr(0, p1));
        string p = trim(line.substr(p1 + 1, p2 - p1 - 1));
        string o = trim(line.substr(p2 + 1));

        if (p == pred1) first_hop.push_back({s, o});
        if (p == pred2) second_hop.push_back({s, o});
    }

    struct Result {
        string x, y, z;
        bool operator<(const Result& o) const {
            if (x != o.x) return x < o.x;
            if (y != o.y) return y < o.y;
            return z < o.z;
        }
    };

    vector<Result> results;
    for (const auto& h1 : first_hop) {
        for (const auto& h2 : second_hop) {
            if (h1.second == h2.first) {
                results.push_back({h1.first, h1.second, h2.second});
            }
        }
    }

    sort(results.begin(), results.end());

    cout << "[";
    for (size_t i = 0; i < results.size(); ++i) {
        cout << "{\"start_node\":\"" << results[i].x << "\",\"bridge_node\":\"" << results[i].y << "\",\"target_node\":\"" << results[i].z << "\"}";
        if (i + 1 < results.size()) cout << ",";
    }
    cout << "]\n";

    return 0;
}
EOF

g++ -O2 -o /app/kg_matcher /tmp/kg_matcher.cpp
strip /app/kg_matcher
rm /tmp/kg_matcher.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
