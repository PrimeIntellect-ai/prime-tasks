#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <sstream>

using namespace std;

struct Edge {
    string u, rel, v;
};

int main() {
    string line;
    vector<Edge> edges;
    bool in_graph = false;

    while (getline(cin, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line == "GRAPH") {
            in_graph = true;
            continue;
        }
        if (line == "END") {
            in_graph = false;
            continue;
        }
        if (in_graph) {
            stringstream ss(line);
            string u, rel, v;
            if (ss >> u >> rel >> v) {
                edges.push_back({u, rel, v});
            }
        } else if (line.rfind("CHAIN ", 0) == 0) {
            stringstream ss(line.substr(6));
            string rel;
            vector<string> chain;
            while (ss >> rel) chain.push_back(rel);

            cout << line << ":" << endl;

            set<pair<string, string>> results;

            set<string> nodes;
            for (auto& e : edges) { nodes.insert(e.u); nodes.insert(e.v); }

            for (const string& start_node : nodes) {
                set<string> current = {start_node};
                for (const string& r : chain) {
                    set<string> next_nodes;
                    for (const string& curr : current) {
                        for (auto& e : edges) {
                            if (e.u == curr && e.rel == r) {
                                next_nodes.insert(e.v);
                            }
                        }
                    }
                    current = next_nodes;
                }
                for (const string& end_node : current) {
                    results.insert({start_node, end_node});
                }
            }

            if (results.empty()) {
                cout << "NONE" << endl;
            } else {
                for (auto& p : results) {
                    cout << p.first << " " << p.second << endl;
                }
            }
        }
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/query_oracle
    strip /app/query_oracle
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
