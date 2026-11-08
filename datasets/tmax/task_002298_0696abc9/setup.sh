#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev
    pip3 install pytest numpy scipy h5py

    mkdir -p /app/training_data/clean /app/training_data/evil
    mkdir -p /app/hidden_corpus/clean /app/hidden_corpus/evil

    # Write C program
    cat << 'EOF' > /app/sensor_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <hdf5.h>

double rand_normal() {
    double u1 = ((double) rand() / (RAND_MAX));
    double u2 = ((double) rand() / (RAND_MAX));
    if (u1 <= 0.0) u1 = 1e-9;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char** argv) {
    if (argc > 1) {
        srand(atoi(argv[1]));
    } else {
        srand(42);
    }

    float data[10000];
    for(int i=0; i<10000; i++) {
        data[i] = (float)rand_normal();
    }

    hid_t file_id = H5Fcreate("sim_output.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    hsize_t dims[1] = {10000};
    hid_t dataspace_id = H5Screate_simple(1, dims, NULL);
    hid_t dataset_id = H5Dcreate2(file_id, "/sensor_data", H5T_NATIVE_FLOAT, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

    H5Dwrite(dataset_id, H5T_NATIVE_FLOAT, H5S_ALL, H5S_ALL, H5P_DEFAULT, data);

    H5Dclose(dataset_id);
    H5Sclose(dataspace_id);
    H5Fclose(file_id);

    return 0;
}
EOF

    # Compile and strip
    gcc -O2 /app/sensor_sim.c -o /app/sensor_sim -I/usr/include/hdf5/serial -L/usr/lib/x86_64-linux-gnu/hdf5/serial -lhdf5 -lm
    strip /app/sensor_sim
    rm /app/sensor_sim.c

    # Generate HDF5 files using a python script to avoid timeout
    cat << 'EOF' > /app/gen_data.py
import h5py
import numpy as np
import os

def gen_files(dir_path, n, dist_type):
    os.makedirs(dir_path, exist_ok=True)
    for i in range(n):
        if dist_type == 'clean':
            data = np.random.normal(0, 1.0, 10000).astype(np.float32)
        else:
            data = np.random.laplace(0, 0.70710678, 10000).astype(np.float32)
        with h5py.File(f"{dir_path}/file_{i}.h5", 'w') as f:
            f.create_dataset("/sensor_data", data=data)

gen_files('/app/training_data/clean', 20, 'clean')
gen_files('/app/training_data/evil', 20, 'evil')
gen_files('/app/hidden_corpus/clean', 100, 'clean')
gen_files('/app/hidden_corpus/evil', 100, 'evil')
EOF

    python3 /app/gen_data.py
    rm /app/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
