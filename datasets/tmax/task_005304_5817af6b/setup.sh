#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make strace
    pip3 install pytest

    mkdir -p /home/user/project/src
    cd /home/user/project

    cat << 'EOF' > env.sh
export CXX=g++
export CXXFLAGS="-O2 -std=c++11"
# INJECTED BUG: Invalid library path
export LDFLAGS="-L/invalid/path/that/breaks/build"
EOF

    cat << 'EOF' > src/calc_weights.cpp
#include <iostream>
#include <fstream>
#include <cmath>
#include <string>
#include <unistd.h>

int main() {
    // Hidden file path that requires strace to find easily
    std::string path = "/tmp/.sim_config_" + std::to_string(getuid()) + ".dat";
    std::ifstream infile(path);
    if (!infile.is_open()) {
        std::cerr << "Failed to open input config." << std::endl;
        return 1;
    }
    double x;
    if (!(infile >> x)) {
        return 1;
    }

    // INJECTED BUG: Numerical instability for x near 0
    double weight = (std::exp(x) - 1.0) / x;

    std::ofstream outfile("weights.bin");
    outfile << weight << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > src/main.cpp
#include <iostream>
#include <fstream>

int main() {
    std::ifstream infile("weights.bin");
    double w;
    if (infile >> w) {
        std::cout << w << std::endl;
        return 0;
    }
    return 1;
}
EOF

    cat << 'EOF' > Makefile
all: sim_app

calc_weights: src/calc_weights.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $< -o $@

weights.bin: calc_weights
	./calc_weights

sim_app: src/main.cpp weights.bin
	$(CXX) $(CXXFLAGS) $(LDFLAGS) src/main.cpp -o $@

clean:
	rm -f calc_weights sim_app weights.bin
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
