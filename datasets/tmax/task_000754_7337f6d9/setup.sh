#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/uptime_monitor
    cd /home/user/uptime_monitor

    # Generate buggy monitor.cpp
    cat << 'EOF' > monitor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;

unordered_map<string, vector<string>> graph;

void check_uptime(const string& node) {
    // BUG: No cycle detection. Infinite recursion if graph has a cycle.
    for (const string& dep : graph[node]) {
        check_uptime(dep);
    }
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <config_file>" << endl;
        return 1;
    }

    ifstream infile(argv[1]);
    string s1, s2;
    while (infile >> s1 >> s2) {
        graph[s1].push_back(s2);
    }

    for (const auto& pair : graph) {
        check_uptime(pair.first);
    }

    cout << "ALL CHECKS PASSED" << endl;
    return 0;
}
EOF

    # Generate services.txt with a hidden cycle
    cat << 'EOF' > generate_config.py
import random
random.seed(42)

with open("services.txt", "w") as f:
    for i in range(1, 200):
        # Generate some tree-like dependencies
        f.write(f"Service_{i} Service_{i*2}\n")
        f.write(f"Service_{i} Service_{i*2+1}\n")

    # Insert the cycle
    f.write("AuthService DBService\n")
    f.write("DBService CacheService\n")
    f.write("CacheService AuthService\n")

    # Add more noise
    for i in range(200, 300):
        f.write(f"App_{i} App_{i+1}\n")

EOF
    python3 generate_config.py
    rm generate_config.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
