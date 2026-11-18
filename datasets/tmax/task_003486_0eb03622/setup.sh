#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-numpy \
        python3-h5py \
        libhdf5-dev \
        build-essential \
        g++

    pip3 install pytest

    mkdir -p /app/libgraphopt-1.2.0
    cat << 'EOF' > /app/libgraphopt-1.2.0/graphopt.h
#ifndef GRAPHOPT_H
#define GRAPHOPT_H
#include <vector>
#include <string>

class Graph {
public:
    int num_nodes;
    std::vector<std::vector<int>> adj_list;
    Graph(int n);
    void load_topology(const std::string& filename);
};
#endif
EOF

    cat << 'EOF' > /app/libgraphopt-1.2.0/graphopt.cpp
#include "graphopt.h"
#include <fstream>

Graph::Graph(int n) : num_nodes(n), adj_list(n) {}

void Graph::load_topology(const std::string& filename) {
    std::ifstream f(filename);
    int u, v;
    while (f >> u >> v) {
        adj_list[u].push_back(v);
        adj_list[v].push_back(u);
    }
}
EOF

    cat << 'EOF' > /app/libgraphopt-1.2.0/Makefile
CXX = g++-7
CXXFLAGS = -O2 -Wall -fPIC

all: libgraphopt.a

libgraphopt.a: graphopt.o
	ar rcs $@ $^

graphopt.o: graphopt.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import h5py

N = 10
A = np.zeros((N, N))
with open('/home/user/data/topology.txt', 'w') as f:
    for i in range(N):
        f.write(f"{i} {(i+1)%N}\n")
        A[i, (i+1)%N] = 1.0
        A[(i+1)%N, i] = 1.0

np.random.seed(42)
initial_dist = np.random.rand(N)
initial_dist /= np.sum(initial_dist)

alpha_true = np.random.uniform(0.02, 0.08, N)

x = initial_dist.copy()
diag_alpha = np.diag(alpha_true)
for _ in range(10):
    x = x + diag_alpha @ A @ x

target_dist = x / np.sum(x)

with h5py.File('/home/user/data/network_states.h5', 'w') as f:
    f.create_dataset('initial_dist', data=initial_dist)
    f.create_dataset('target_dist', data=target_dist)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
