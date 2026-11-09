#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create the legacy graph oracle source
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

struct Node {
    char name[16];
    int64_t timestamp;
    int64_t padding;
};

struct Edge {
    int32_t src;
    int32_t dst;
    float weight;
};

int main() {
    std::ifstream in("/home/user/graph.bin", std::ios::binary);
    if (!in) return 1;
    char magic[4];
    if (!in.read(magic, 4)) return 1;
    if (magic[0] != 'G' || magic[1] != 'R' || magic[2] != 'P' || magic[3] != 'H') return 1;
    int32_t N;
    if (!in.read(reinterpret_cast<char*>(&N), 4)) return 1;
    std::vector<Node> nodes(N);
    if (!in.read(reinterpret_cast<char*>(nodes.data()), N * sizeof(Node))) return 1;
    int32_t E;
    if (!in.read(reinterpret_cast<char*>(&E), 4)) return 1;
    std::vector<Edge> edges(E);
    if (!in.read(reinterpret_cast<char*>(edges.data()), E * sizeof(Edge))) return 1;

    return 0;
}
EOF

    # Compile and strip the oracle
    g++ -O2 /tmp/oracle.cpp -o /app/legacy_graph_oracle
    strip /app/legacy_graph_oracle
    rm /tmp/oracle.cpp

    # Generate raw_datasets.csv
    cat << 'EOF' > /home/user/raw_datasets.csv
source,target,weight,source_date,target_date
D1,D2,1.0,2021-05-02,2021-05-03
D2,D99,2.0,2021-05-03,2021-06-01
D1,D3,5.0,2021-05-02,2021-05-04
D3,D99,1.0,2021-05-04,2021-06-01
EOF

    chmod -R 777 /home/user
