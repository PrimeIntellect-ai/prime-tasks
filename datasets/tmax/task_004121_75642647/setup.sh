#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest pandas

    mkdir -p /app
    mkdir -p /home/user

    # Create nodes.csv
    cat << 'EOF' > /home/user/nodes.csv
node_id,label
1,A
2,B
3,C
400,D
500,E
600,F
700,G
EOF

    # Create edges.csv
    cat << 'EOF' > /home/user/edges.csv
source,target,weight
1,2,10
2,3,15
EOF

    # Create audio file
    espeak -w /app/update.wav "Please update the dataset. Add an edge from 400 to 500 with weight 20. Add an edge from 500 to 600 with weight 30. Add an edge from 600 to 700 with weight 40. Finally, make sure to output exactly the top 15 results in the final report."

    # Create buggy C++ code
    cat << 'EOF' > /home/user/process_graph.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>

struct Edge {
    int source;
    int target;
    int weight;
};

int main() {
    // Buggy implementation with implicit cross join
    std::vector<Edge> edges;
    // ... reading edges ...

    std::ofstream out("/home/user/final_results.csv");
    out << "source,target,total_weight\n";
    out.close();
    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
