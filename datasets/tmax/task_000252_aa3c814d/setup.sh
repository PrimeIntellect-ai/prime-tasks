#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/legacy_router.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <queue>
#include <thread>
#include <chrono>
#include <algorithm>

using namespace std;

struct Edge {
    string to;
    long long cost;
};

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    string file = argv[1];
    string start = argv[2];
    string end = argv[3];

    ifstream in(file);
    string link, u, v;
    long long lat, jit, drop;

    unordered_map<string, vector<Edge>> graph;

    while (in >> link >> u >> v >> lat >> jit >> drop) {
        long long cost = lat + (jit * 2) + (drop * 100);
        graph[u].push_back({v, cost});
        graph[v].push_back({u, cost});
        this_thread::sleep_for(chrono::milliseconds(1));
    }

    unordered_map<string, long long> dist;
    unordered_map<string, string> prev;
    for (auto& p : graph) {
        dist[p.first] = 1e18;
    }
    dist[start] = 0;

    vector<string> unvisited;
    for (auto& p : graph) unvisited.push_back(p.first);

    while (!unvisited.empty()) {
        string u_node = "";
        long long min_d = 1e18;
        for (auto& n : unvisited) {
            if (dist[n] < min_d) {
                min_d = dist[n];
                u_node = n;
            }
        }
        if (u_node == "" || u_node == end) break;

        unvisited.erase(remove(unvisited.begin(), unvisited.end(), u_node), unvisited.end());

        for (auto& edge : graph[u_node]) {
            if (dist[u_node] + edge.cost < dist[edge.to]) {
                dist[edge.to] = dist[u_node] + edge.cost;
                prev[edge.to] = u_node;
            }
        }
    }

    if (dist.find(end) == dist.end() || dist[end] == 1e18) {
        cout << "No path found\n";
        return 0;
    }

    vector<string> path;
    string curr = end;
    while (curr != start) {
        path.push_back(curr);
        curr = prev[curr];
    }
    path.push_back(start);
    reverse(path.begin(), path.end());

    cout << "Path: ";
    for (size_t i = 0; i < path.size(); ++i) {
        cout << path[i] << (i + 1 == path.size() ? "" : " -> ");
    }
    cout << "\nTotal Cost: " << dist[end] << "\n";

    return 0;
}
EOF

g++ -O3 -o /app/legacy_router /app/legacy_router.cpp
strip /app/legacy_router
rm /app/legacy_router.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
