#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional required packages
    apt-get install -y libhdf5-dev hdf5-tools
    pip3 install h5py numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the C program
    cat << 'EOF' > /home/user/simulate_markov.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "hdf5.h"

#define N 50

int main(int argc, char **argv) {
    if (argc != 3) return 1;

    hid_t file_id, dataset_id;
    double P[N][N];
    double P_new[N][N];

    file_id = H5Fopen(argv[1], H5F_ACC_RDONLY, H5P_DEFAULT);
    dataset_id = H5Dopen(file_id, "P", H5P_DEFAULT);
    H5Dread(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, P);
    H5Dclose(dataset_id);
    H5Fclose(file_id);

    double D = 0.1;
    double dx = 1.0;

    // BUG: dt is too large for the CFL condition dt <= dx^2 / (4D) = 2.5
    // 5.0 causes divergence.
    double dt = 5.0; 

    double T = 10.0;
    int steps = (int)(T / dt);

    for (int t = 0; t < steps; t++) {
        for (int i = 0; i < N; i++) {
            for (int j = 0; j < N; j++) {
                P_new[i][j] = P[i][j];
                if (i > 0 && i < N-1 && j > 0 && j < N-1) {
                    double lap = P[i-1][j] + P[i+1][j] + P[i][j-1] + P[i][j+1] - 4.0 * P[i][j];
                    P_new[i][j] += D * dt * lap / (dx * dx);
                }
            }
        }
        for (int i = 0; i < N; i++) {
            for (int j = 0; j < N; j++) {
                P[i][j] = P_new[i][j];
            }
        }
    }

    file_id = H5Fcreate(argv[2], H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    hsize_t dims[2] = {N, N};
    hid_t dataspace_id = H5Screate_simple(2, dims, NULL);
    dataset_id = H5Dcreate(file_id, "P", H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, P);
    H5Dclose(dataset_id);
    H5Sclose(dataspace_id);
    H5Fclose(file_id);

    return 0;
}
EOF

    # Create python setup script to generate HDF5 files and truth
    cat << 'EOF' > /tmp/setup.py
import h5py
import numpy as np

N = 50
P = np.zeros((N, N))
P[N//2, N//2] = 1.0

with h5py.File('/home/user/init.h5', 'w') as f:
    f.create_dataset('P', data=P)

# D = 0.1, dx = 1.0. Max dt = 1.0 / 0.4 = 2.5
# We simulate ref with D=0.12, dx=1.0, dt=1.0, T=10.0 (10 steps)
P_ref = P.copy()
D_ref = 0.12
dt_ref = 1.0
steps = 10

for _ in range(steps):
    lap = np.zeros_like(P_ref)
    lap[1:-1, 1:-1] = P_ref[:-2, 1:-1] + P_ref[2:, 1:-1] + P_ref[1:-1, :-2] + P_ref[1:-1, 2:] - 4*P_ref[1:-1, 1:-1]
    P_ref += D_ref * dt_ref * lap

with h5py.File('/home/user/ref.h5', 'w') as f:
    f.create_dataset('P', data=P_ref)

# Simulate expected out.h5
# D = 0.1, dx = 1.0, dt fixed to max stable: dt = 1.0^2 / (4*0.1) = 2.5
# T = 10.0, so 4 steps
P_out = P.copy()
D_out = 0.1
dt_out = 2.5
steps_out = 4

for _ in range(steps_out):
    lap = np.zeros_like(P_out)
    lap[1:-1, 1:-1] = P_out[:-2, 1:-1] + P_out[2:, 1:-1] + P_out[1:-1, :-2] + P_out[1:-1, 2:] - 4*P_out[1:-1, 1:-1]
    P_out += D_out * dt_out * lap

tv_dist = 0.5 * np.sum(np.abs(P_out - P_ref))
with open('/home/user/.truth_tv.txt', 'w') as f:
    f.write(f"{tv_dist:.4f}\n")
EOF

    # Run the setup script
    python3 /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
