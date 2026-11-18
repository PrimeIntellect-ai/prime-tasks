#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/heat_sim.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <N> <M> <alpha>\n";
        return 1;
    }
    int N = std::atoi(argv[1]);
    int M = std::atoi(argv[2]);
    double alpha = std::atof(argv[3]);

    double dx = 1.0 / N;
    double dt = 0.5 / M;
    double r = alpha * dt / (dx * dx);

    std::vector<double> u(N + 1, 0.0);
    // Initial condition: u(x,0) = sin(pi * x)
    for (int i = 0; i <= N; ++i) {
        u[i] = std::sin(M_PI * i * dx);
    }

    std::vector<double> u_new = u;
    for (int n = 0; n < M; ++n) {
        for (int i = 1; i < N; ++i) {
            u_new[i] = u[i] + r * (u[i+1] - 2.0 * u[i] + u[i-1]);
        }
        u = u_new;
    }

    std::cout << "x,u\n";
    for (int i = 0; i <= N; ++i) {
        std::cout << i * dx << "," << u[i] << "\n";
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/generate_ref.py
import math

alpha = 0.04
t = 0.5
N_ref = 1000
dx = 1.0 / N_ref

with open("/home/user/reference.csv", "w") as f:
    f.write("x,u\n")
    for i in range(N_ref + 1):
        x = i * dx
        u = math.sin(math.pi * x) * math.exp(-alpha * math.pi**2 * t)
        f.write(f"{x},{u}\n")
EOF

python3 /home/user/generate_ref.py
rm /home/user/generate_ref.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
