#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libeigen3-dev libfftw3-dev libhdf5-dev
    pip3 install pytest numpy h5py

    mkdir -p /app
    cat << 'EOF' > /app/wave_sim.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 5) return 1;
    int nx = std::stoi(argv[1]);
    int ny = std::stoi(argv[2]);
    int nt = std::stoi(argv[3]);
    std::string out_file = argv[4];

    std::vector<float> data(nx * ny * nt);
    std::srand(42); // deterministic seed

    for (int x = 0; x < nx; ++x) {
        for (int y = 0; y < ny; ++y) {
            for (int t = 0; t < nt; ++t) {
                // Dominant frequency at index 50, secondary at 120
                float val = 2.0 * std::sin(2.0 * M_PI * 50 * t / nt) * std::cos(M_PI * x / nx) * std::sin(M_PI * y / ny) +
                            0.8 * std::sin(2.0 * M_PI * 120 * t / nt) * std::sin(2.0 * M_PI * x / nx) * std::cos(2.0 * M_PI * y / ny);

                float noise = 0.05 * ((float)std::rand() / RAND_MAX - 0.5f);
                data[(x * ny + y) * nt + t] = val + noise;
            }
        }
    }

    std::ofstream out(out_file, std::ios::binary);
    out.write(reinterpret_cast<char*>(data.data()), data.size() * sizeof(float));
    out.close();
    return 0;
}
EOF

    g++ -O3 /app/wave_sim.cpp -o /app/wave_sim
    rm /app/wave_sim.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
