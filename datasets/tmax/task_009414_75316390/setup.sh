#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00  0.00           N
ATOM      2  CA  ALA A   1      11.500  10.000  10.000  1.00  0.00           C
ATOM      3  C   ALA A   1      12.000  11.500  10.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/mc_volume.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <omp.h>
#include <random>
#include <iomanip>

struct Atom { float x, y, z, r; };

int main() {
    std::vector<Atom> atoms;
    std::ifstream in("/home/user/protein.pdb");
    std::string line;
    while(std::getline(in, line)) {
        if(line.substr(0,4) == "ATOM") {
            float x = std::stof(line.substr(30, 8));
            float y = std::stof(line.substr(38, 8));
            float z = std::stof(line.substr(46, 8));
            atoms.push_back({x, y, z, 1.5f});
        }
    }

    int num_samples = 1000000;
    float box_size = 20.0f;
    float box_volume = box_size * box_size * box_size;

    float total_volume = 0.0f;
    float vol_per_sample = box_volume / num_samples;

    #pragma omp parallel for reduction(+:total_volume)
    for(int i = 0; i < num_samples; i++) {
        std::mt19937 gen(42 + i);
        std::uniform_real_distribution<float> dist(0.0f, box_size);
        float px = dist(gen);
        float py = dist(gen);
        float pz = dist(gen);

        bool hit = false;
        for(const auto& atom : atoms) {
            float dx = px - atom.x;
            float dy = py - atom.y;
            float dz = pz - atom.z;
            if(dx*dx + dy*dy + dz*dz < atom.r * atom.r) {
                hit = true;
                break;
            }
        }
        if(hit) {
            total_volume += vol_per_sample;
        }
    }

    std::cout << std::fixed << std::setprecision(6) << total_volume << std::endl;
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
