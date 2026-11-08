#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/fisher_sim.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <cmath>

int main() {
    int N = 100; // TODO: Refine mesh to 1000
    double L = 1.0;
    double dx = L / (N - 1);
    double D = 0.01;
    double r = 1.0;
    double T = 1.0;

    // Diverging dt! TODO: Fix to dt = 0.4 * (dx * dx) / D
    double dt = 0.01;
    int steps = std::ceil(T / dt);

    std::vector<double> u(N, 0.0);
    for(int i=0; i<N/10; ++i) u[i] = 1.0;

    std::vector<double> u_new = u;

    for(int t=0; t<steps; ++t) {
        // TODO: Parallelize this loop with OpenMP
        for(int i=1; i<N-1; ++i) {
            double diffusion = D * (u[i+1] - 2*u[i] + u[i-1]) / (dx*dx);
            double reaction = r * u[i] * (1 - u[i]);
            u_new[i] = u[i] + dt * (diffusion + reaction);
        }
        u = u_new;
    }

    std::ofstream out("final_state.txt");
    for(int i=0; i<N; ++i) out << i * dx << " " << u[i] << "\n";
    return 0;
}
EOF

    chmod -R 777 /home/user
