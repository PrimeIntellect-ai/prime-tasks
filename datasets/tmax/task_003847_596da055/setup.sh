#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest flask

    mkdir -p /app/graph-sim-1.0/src
    mkdir -p /app/graph-sim-1.0/bin

    cat << 'EOF' > /app/graph-sim-1.0/Makefile
CXX=g++
CXXFLAGS=-O2 -fopenmp -std=c++11
LDFLAGS=-fopenmp

all: bin/simulate_graph

bin/simulate_graph: src/simulator.cpp
	mkdir -p bin
	$(CXX) $(CXXFLAGS) $(LDFLAGS) src/simulator.cpp -o bin/simulate_graph
EOF

    cat << 'EOF' > /app/graph-sim-1.0/src/simulator.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <fstream>
#include <omp.h>
#include <algorithm>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::vector<float> densities;
    for(int i=0; i<10000; ++i) {
        // Pseudo-random deterministic values simulating graph node densities
        densities.push_back( sin(i) * sin(i) * 100.0f );
    }

    // The bug: Non-reproducible reduction
    float total = 0.0f;
    #pragma omp parallel for reduction(+:total)
    for(int i=0; i<densities.size(); ++i) {
        total += densities[i] / 3.0f;
    }

    // Output densities
    for(int i=0; i<10; ++i) {
        std::cout << densities[i] + total*0.000001f << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/molecule_graph.dat
Nodes: 10000
Edges: 45000
EOF

    cat << 'EOF' > /app/reference_data.csv
50.0010,35.3560
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
