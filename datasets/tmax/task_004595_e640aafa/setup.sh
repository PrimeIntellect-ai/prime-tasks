#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libhdf5-dev gcc file binutils
    pip3 install pytest h5py

    mkdir -p /app
    cat << 'EOF' > /app/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <hdf5.h>

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    hid_t file_id, dataset_id;
    double params[3];
    file_id = H5Fopen(argv[1], H5F_ACC_RDONLY, H5P_DEFAULT);
    if(file_id < 0) return 1;
    dataset_id = H5Dopen(file_id, "/initial_state", H5P_DEFAULT);
    H5Dread(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, params);
    H5Dclose(dataset_id);
    H5Fclose(file_id);

    double x = params[0];
    double v = params[1];
    double dt = params[2];
    double t = 0.0;

    // Simple Euler integrator with flawed adaptive step size
    while(t < 5.0) {
        double a = -1.5 * x - 0.5 * v;
        double current_dt = dt / (1.0 + fabs(v));
        if (t + current_dt > 5.0) {
            current_dt = 5.0 - t;
        }
        x = x + v * current_dt;
        v = v + a * current_dt;
        t = t + current_dt;
    }

    printf("%.5f\n", x);
    return 0;
}
EOF

    h5cc -O2 -o /app/profiler_sim /app/sim.c -lm
    strip /app/profiler_sim
    chmod +x /app/profiler_sim
    rm /app/sim.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
