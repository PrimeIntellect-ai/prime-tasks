#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libgl1 libglib2.0-0
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user/sim_src

    cat << 'EOF' > /tmp/make_video.py
import numpy as np
import cv2

N = 64
T = 100
D_true = 0.08
dt = 0.5
dx = 1.0

# Initialize field
u = np.zeros((N, N))
u[20:40, 20:40] = 1.0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/thermal_diffusion.mp4', fourcc, 10.0, (N, N), False)

for t in range(T):
    # Diffuse
    laplacian = (
        np.roll(u, 1, axis=0) + np.roll(u, -1, axis=0) +
        np.roll(u, 1, axis=1) + np.roll(u, -1, axis=1) - 4*u
    ) / (dx**2)
    u = u + D_true * dt * laplacian

    # Write frame
    frame = (u / np.max(u) * 255).astype(np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/make_video.py

    cat << 'EOF' > /home/user/sim_src/heat_solver.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <cstdlib>

#define N 16

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    double D = atof(argv[1]);
    int T = 100;
    double dt = 0.5;

    vector<vector<double>> u(N, vector<double>(N, 0.0));
    // Initial condition mapped to arbitrary N
    int start = N * 20 / 64;
    int end = N * 40 / 64;
    for(int i=start; i<end; ++i) {
        for(int j=start; j<end; ++j) {
            u[i][j] = 1.0;
        }
    }

    ofstream out("sim_output.csv");
    for (int t = 0; t < T; ++t) {
        vector<vector<double>> unew = u;
        for (int i = 0; i < N; ++i) {
            for (int j = 0; j < N; ++j) {
                double up = u[(i+1)%N][j];
                double um = u[(i-1+N)%N][j];
                double vp = u[i][(j+1)%N];
                double vm = u[i][(j-1+N)%N];
                unew[i][j] = u[i][j] + D * dt * (up + um + vp + vm - 4*u[i][j]);
            }
        }
        u = unew;

        for (int i = 0; i < N; ++i) {
            for (int j = 0; j < N; ++j) {
                out << u[i][j] << (i==N-1 && j==N-1 ? "" : ",");
            }
        }
        out << "\n";
    }
    out.close();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim_src/Makefile
all:
	g++ -O3 heat_solver.cpp -o heat_solver
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim_src
    chmod -R 777 /home/user
    chmod -R 777 /app
