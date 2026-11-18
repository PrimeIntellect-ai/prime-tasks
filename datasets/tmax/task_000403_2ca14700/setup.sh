#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest networkx

    mkdir -p /app

    cat << 'EOF' > /app/route_calc.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <map>
#include <queue>
#include <limits>
#include <algorithm>
#include <nlohmann/json.hpp>

using json = nlohmann::json;
using namespace std;

struct Edge {
    string dst;
    int cost;
};

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    ifstream i(argv[1]);
    json j;
    i >> j;
    string target = argv[2];

    map<string, vector<Edge>> graph;
    vector<string> storage_nodes;

    for (auto& node : j["nodes"]) {
        if (node.value("is_backup_storage", false)) {
            storage_nodes.push_back(node["id"]);
        }
    }

    for (auto& edge : j["edges"]) {
        int cost = edge["latency_ms"].get<int>() + (edge["throughput_penalty"].get<int>() * 2);
        graph[edge["src"]].push_back({edge["dst"], cost});
    }

    map<string, int> dist;
    map<string, vector<string>> paths;

    for (auto& n : j["nodes"]) {
        dist[n["id"]] = numeric_limits<int>::max();
    }

    priority_queue<pair<int, string>, vector<pair<int, string>>, greater<pair<int, string>>> pq;

    for (auto& s : storage_nodes) {
        dist[s] = 0;
        paths[s] = {s};
        pq.push({0, s});
    }

    while (!pq.empty()) {
        auto top = pq.top();
        int d = top.first;
        string u = top.second;
        pq.pop();

        if (d > dist[u]) continue;

        for (auto& edge : graph[u]) {
            string v = edge.dst;
            int cost = edge.cost;
            vector<string> new_path = paths[u];
            new_path.push_back(v);

            if (dist[u] + cost < dist[v]) {
                dist[v] = dist[u] + cost;
                paths[v] = new_path;
                pq.push({dist[v], v});
            } else if (dist[u] + cost == dist[v]) {
                if (new_path < paths[v]) {
                    paths[v] = new_path;
                    pq.push({dist[v], v});
                }
            }
        }
    }

    json out = paths[target];
    if (paths.find(target) == paths.end()) {
        out = json::array();
    }
    cout << out.dump() << endl;
    return 0;
}
EOF

    g++ -O3 -s /app/route_calc.cpp -o /app/route_calc
    rm /app/route_calc.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
