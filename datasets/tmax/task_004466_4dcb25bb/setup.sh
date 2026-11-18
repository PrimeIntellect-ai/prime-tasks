#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create directories
    mkdir -p /app/libinfer_ops-1.2.0
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create Makefile with perturbation
    cat << 'EOF' > /app/libinfer_ops-1.2.0/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O3

all: benchmark_infer

benchmark_infer: tracker.cpp
	$(CXX) $(CXXFLAGS) -o benchmark_infer tracker.cpp

clean:
	rm -f benchmark_infer
EOF

    # Create tracker.cpp requiring C++17
    cat << 'EOF' > /app/libinfer_ops-1.2.0/tracker.cpp
#include <iostream>
#include <fstream>
#include <optional>
#include <variant>

int main() {
    std::optional<int> opt = 1;
    std::variant<int, float> var = 1.0f;
    std::ofstream out("baseline_perf.txt");
    if (out.is_open()) {
        out << "TRACKER_OVERHEAD_MS: 0.04\n";
        out.close();
    }
    return 0;
}
EOF

    # Generate corpora using Python
    python3 -c "
import os
import random
import math

random.seed(42)

for i in range(50):
    with open(f'/app/corpora/clean/clean_{i}.csv', 'w') as f:
        f.write('latency_ms\n')
        for _ in range(200):
            if random.random() < 0.04:
                f.write('-1.0\n')
            else:
                # Log-normal with mean ~30
                val = random.lognormvariate(math.log(25), 0.5)
                f.write(f'{val:.4f}\n')

for i in range(50):
    with open(f'/app/corpora/evil/evil_{i}.csv', 'w') as f:
        f.write('latency_ms\n')
        if i < 25:
            # > 20% missing
            for _ in range(200):
                if random.random() < 0.3:
                    f.write('NaN\n')
                else:
                    f.write('30.0\n')
        else:
            # Upper bound > 100ms
            for _ in range(200):
                if random.random() < 0.01:
                    f.write('-1.0\n')
                else:
                    f.write('150.0\n')
"

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
