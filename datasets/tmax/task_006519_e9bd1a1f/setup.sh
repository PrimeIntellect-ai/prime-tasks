#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user/backup_tool
cd /home/user/backup_tool

cat << 'EOF' > edges.csv
source_node,target_node,latency
A,B,10
B,C,15
A,C,30
C,D,10
B,E,20
E,F,5
D,F,10
EOF

cat << 'EOF' > jobs.csv
job_id,source_node,target_node
J1,A,D
J2,A,F
J3,B,D
J4,E,C
J5,C,F
J6,A,C
EOF

cat << 'EOF' > router.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <sstream>
#include <algorithm>

using namespace std;

struct Edge {
    string target;
    int weight;
};

struct Job {
    string id;
    string source;
    string target;
};

// TODO: Fix the data structures and algorithms

int main() {
    // Read edges
    // Read jobs

    // Buggy logic: Implicit cross join
    // for job in jobs: for edge in edges: total_cost += edge.weight ...

    // TODO: 
    // 1. Build undirected graph
    // 2. Compute shortest paths (Dijkstra)
    // 3. Compute degree centrality
    // 4. Sort and filter
    // 5. Write to /home/user/top_jobs.csv (top 3)
    // 6. Write to /home/user/top_hubs.csv (top 3)

    return 0;
}
EOF

cat << 'EOF' > Makefile
all: router

router: router.cpp
	g++ -O3 -std=c++17 router.cpp -o router

clean:
	rm -f router
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/backup_tool
chmod -R 777 /home/user
