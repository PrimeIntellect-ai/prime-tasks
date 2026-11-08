#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make cmake protobuf-compiler libprotobuf-dev
    pip3 install pytest

    mkdir -p /app/bin /app/schema /home/user/workspace

    cat << 'EOF' > /app/schema/deps.proto
syntax = "proto3";
package builddeps;

message Node {
  int32 id = 1;
  repeated int32 dependencies = 2; // Node IDs that this node depends on (directed edge: dependency -> id)
}

message Graph {
  repeated Node nodes = 1;
}
EOF

    cd /app/schema
    protoc --cpp_out=. deps.proto

    cat << 'EOF' > /app/schema/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <queue>
#include <map>
#include <set>
#include <algorithm>
#include "deps.pb.h"

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    builddeps::Graph graph;
    fstream input(argv[1], ios::in | ios::binary);
    if (!graph.ParseFromIstream(&input)) return 1;

    map<int, int> in_degree;
    map<int, vector<int>> adj;
    set<int> all_nodes;

    for (const auto& node : graph.nodes()) {
        all_nodes.insert(node.id());
        in_degree[node.id()] += 0;
        for (int dep : node.dependencies()) {
            adj[dep].push_back(node.id());
            in_degree[node.id()]++;
            all_nodes.insert(dep);
            in_degree[dep] += 0;
        }
    }

    priority_queue<int, vector<int>, greater<int>> pq;
    for (int node : all_nodes) {
        if (in_degree[node] == 0) {
            pq.push(node);
        }
    }

    vector<int> build_order;
    while (!pq.empty()) {
        int u = pq.top();
        pq.pop();
        build_order.push_back(u);
        for (int v : adj[u]) {
            in_degree[v]--;
            if (in_degree[v] == 0) {
                pq.push(v);
            }
        }
    }

    if (build_order.size() == all_nodes.size()) {
        cout << "BUILD:";
        for (int node : build_order) {
            cout << " " << node;
        }
        cout << endl;
    } else {
        vector<int> unresolved;
        for (int node : all_nodes) {
            if (in_degree[node] > 0) {
                unresolved.push_back(node);
            }
        }
        sort(unresolved.begin(), unresolved.end());
        cout << "CYCLE_DETECTED: unresolved_count=" << unresolved.size() << " nodes=";
        for (size_t i = 0; i < unresolved.size(); ++i) {
            cout << unresolved[i] << (i + 1 == unresolved.size() ? "" : ",");
        }
        cout << endl;
    }

    return 0;
}
EOF

    g++ -O3 oracle.cpp deps.pb.cc -o /app/bin/dep_solver_oracle -lprotobuf
    strip /app/bin/dep_solver_oracle

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
