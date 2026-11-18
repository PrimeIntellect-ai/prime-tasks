#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim_src

    cat << 'EOF' > /home/user/raw_data.json
{
    "metadata": "observational_data_v2",
    "infection_count_day_1": 10,
    "infection_count_day_15": 142,
    "infection_count_day_30": 634,
    "notes": "Day 30 is the critical threshold"
}
EOF

    cat << 'EOF' > /home/user/sim_src/sim.cpp
#include <iostream>
#include <random>
#include <cstdlib>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    double beta = std::stod(argv[1]);
    int N = std::stoi(argv[2]);
    int seed = std::stoi(argv[3]);

    std::mt19937 gen(seed);
    std::uniform_real_distribution<> dis(0.0, 1.0);

    int I = 10;
    int S = N - I;

    for (int t = 0; t < 30; ++t) {
        int new_infections = 0;
        for(int i=0; i<S; ++i) {
            if (dis(gen) < beta * I / N) {
                new_infections++;
            }
        }
        S -= new_infections;
        I += new_infections;
    }
    std::cout << I << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
