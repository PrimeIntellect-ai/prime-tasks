#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/analyst_notes.wav "For the new pipeline, the C++ query tool needs to output all nodes reachable from the starting node. However, it should only traverse edges where the relationship type is exactly depends_on or includes. Ignore any other relationships. The output must be a simple list of reachable node IDs, excluding the starting node itself, sorted lexicographically, with each node ID on its own line."

    # Create the oracle C++ source
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <set>
#include <queue>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    string filename = argv[1];
    string start_node = argv[2];

    unordered_map<string, vector<string>> graph;
    ifstream file(filename);
    string line;
    while (getline(file, line)) {
        if (line.empty()) continue;
        if (line.back() == '\r') line.pop_back();
        stringstream ss(line);
        string source, target, rel;
        if (getline(ss, source, ',') && getline(ss, target, ',') && getline(ss, rel)) {
            if (rel == "depends_on" || rel == "includes") {
                graph[source].push_back(target);
            }
        }
    }

    set<string> reachable;
    queue<string> q;
    q.push(start_node);
    unordered_set<string> visited;
    visited.insert(start_node);

    while (!q.empty()) {
        string curr = q.front();
        q.pop();
        for (const string& neighbor : graph[curr]) {
            if (visited.find(neighbor) == visited.end()) {
                visited.insert(neighbor);
                reachable.insert(neighbor);
                q.push(neighbor);
            }
        }
    }

    for (const string& node : reachable) {
        cout << node << "\n";
    }

    return 0;
}
EOF

    # Compile the oracle
    g++ -std=c++17 -O2 /app/oracle.cpp -o /app/oracle_kg_query
    rm /app/oracle.cpp

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
