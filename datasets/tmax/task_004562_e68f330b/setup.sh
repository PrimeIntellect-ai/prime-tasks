#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create the legacy deadlock detector source
    cat << 'EOF' > /app/deadlock_detector.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>

using namespace std;

bool hasCycleUtil(const string& v, unordered_map<string, vector<string>>& adj, unordered_set<string>& visited, unordered_set<string>& recStack) {
    if (visited.find(v) == visited.end()) {
        visited.insert(v);
        recStack.insert(v);

        for (const string& neighbor : adj[v]) {
            if (visited.find(neighbor) == visited.end() && hasCycleUtil(neighbor, adj, visited, recStack))
                return true;
            else if (recStack.find(neighbor) != recStack.end())
                return true;
        }
    }
    recStack.erase(v);
    return false;
}

bool hasCycle(unordered_map<string, vector<string>>& adj) {
    unordered_set<string> visited;
    unordered_set<string> recStack;
    for (auto const& pair : adj) {
        if (hasCycleUtil(pair.first, adj, visited, recStack))
            return true;
    }
    return false;
}

int main(int argc, char* argv[]) {
    if (argc != 2) return 0;
    ifstream file(argv[1]);
    string line;
    unordered_map<string, vector<string>> adj;

    while (getline(file, line)) {
        stringstream ss(line);
        string t_id, r_id, status;
        getline(ss, t_id, ',');
        getline(ss, r_id, ',');
        getline(ss, status, ',');

        string t_node = "T" + t_id;
        string r_node = "R" + r_id;

        if (status == "HELD" || status == "HELD\r") {
            adj[r_node].push_back(t_node);
        } else if (status == "WAITING" || status == "WAITING\r") {
            adj[t_node].push_back(r_node);
        }
    }

    if (hasCycle(adj)) {
        return 1;
    }
    return 0;
}
EOF

    g++ -O3 -o /app/deadlock_detector /app/deadlock_detector.cpp
    strip /app/deadlock_detector
    rm /app/deadlock_detector.cpp

    # Create evil corpus (cycle)
    cat << 'EOF' > /app/corpus/evil/evil1.csv
1,1,WAITING
2,1,HELD
2,2,WAITING
1,2,HELD
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.csv
1,10,HELD
2,10,WAITING
2,20,HELD
3,20,WAITING
3,30,HELD
1,30,WAITING
EOF

    # Create clean corpus (no cycle)
    cat << 'EOF' > /app/corpus/clean/clean1.csv
1,1,WAITING
2,1,HELD
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.csv
1,10,HELD
2,10,WAITING
2,20,HELD
3,20,WAITING
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
