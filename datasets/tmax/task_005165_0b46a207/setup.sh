#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    # Create required directories
    mkdir -p /app/data
    mkdir -p /app/tests/evil
    mkdir -p /app/tests/clean

    # Create dummy graph.csv
    echo "source,target,weight" > /app/data/graph.csv
    echo "A,B,10" >> /app/data/graph.csv

    # Create the mock C++ pathfinder binary
    cat << 'EOF' > /tmp/pathfinder.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    bool explain = false;
    std::string query_file = "";

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--explain") {
            explain = true;
        } else if (arg == "--query" && i + 1 < argc) {
            query_file = argv[++i];
        }
    }

    if (!explain || query_file.empty()) {
        return 0;
    }

    std::ifstream file(query_file);
    if (!file.is_open()) {
        std::cerr << "Error opening file: " << query_file << std::endl;
        return 1;
    }

    std::string line;
    bool corrupted = false;
    while (std::getline(file, line)) {
        if (line.find("_STALE_") != std::string::npos) {
            corrupted = true;
            break;
        }
    }

    if (corrupted) {
        std::cout << "[WARN] INDEX_STATE: CORRUPTED\n";
    } else {
        std::cout << "[INFO] INDEX_STATE: VALID\n";
    }

    return 0;
}
EOF

    # Compile and strip the binary
    g++ -O2 -o /app/pathfinder /tmp/pathfinder.cpp
    strip /app/pathfinder
    rm /tmp/pathfinder.cpp

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
