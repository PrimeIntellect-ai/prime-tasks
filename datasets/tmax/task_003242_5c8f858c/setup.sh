#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /tmp/source.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <map>
#include <set>
#include <queue>
#include <algorithm>
#include <nlohmann/json.hpp>

using json = nlohmann::json;
using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <json_file>" << endl;
        return 1;
    }

    ifstream ifs(argv[1]);
    if (!ifs.is_open()) {
        cerr << "Could not open file" << endl;
        return 1;
    }

    json j;
    try {
        ifs >> j;
    } catch (...) {
        cerr << "Invalid JSON" << endl;
        return 1;
    }

    map<string, vector<string>> adj;
    map<string, int> in_degree;
    set<string> all_nodes;

    if (j.contains("libraries")) {
        for (auto& el : j["libraries"].items()) {
            string u = el.key();
            all_nodes.insert(u);
            for (auto& dep : el.value()) {
                string v = dep.get<string>();
                all_nodes.insert(v);
                adj[u].push_back(v);
                in_degree[v]++;
            }
        }
    }

    for (const auto& node : all_nodes) {
        if (in_degree.find(node) == in_degree.end()) {
            in_degree[node] = 0;
        }
    }

    priority_queue<string> pq;
    for (const auto& pair : in_degree) {
        if (pair.second == 0) {
            pq.push(pair.first);
        }
    }

    vector<string> order;
    while (!pq.empty()) {
        string u = pq.top();
        pq.pop();
        order.push_back(u);

        for (const string& v : adj[u]) {
            in_degree[v]--;
            if (in_degree[v] == 0) {
                pq.push(v);
            }
        }
    }

    if (order.size() != all_nodes.size()) {
        cout << "FATAL: Cyclic dependency detected." << endl;
    } else {
        cout << "Link order: ";
        for (size_t i = 0; i < order.size(); ++i) {
            cout << order[i] << (i + 1 == order.size() ? "" : " -> ");
        }
        cout << endl;
    }

    return 0;
}
EOF

    g++ -O3 -s /tmp/source.cpp -o /app/sec_linker_oracle
    rm /tmp/source.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
