#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev binutils
    pip3 install pytest h5py numpy

    mkdir -p /app
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil
    mkdir -p /eval/data/clean
    mkdir -p /eval/data/evil

    cat << 'EOF' > /tmp/preprocessor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <hdf5.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    hid_t file, dataset, space;
    file = H5Fopen(argv[1], H5F_ACC_RDWR, H5P_DEFAULT);
    dataset = H5Dopen(file, "rf_signal", H5P_DEFAULT);
    double data[2000];
    H5Dread(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data);
    for(int i=0; i<2000; i++) {
        data[i] += 1.5 * sin(2.0 * M_PI * 450.0 * (i / 2000.0));
    }
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data);
    H5Dclose(dataset);
    H5Fclose(file);
    return 0;
}
EOF

    h5cc -O2 /tmp/preprocessor.c -o /app/legacy_preprocessor -lm
    strip /app/legacy_preprocessor
    chmod +x /app/legacy_preprocessor

    cat << 'EOF' > /tmp/generate_data.py
import os
import h5py
import numpy as np

def generate_signal(is_evil):
    t = np.linspace(0, 1, 2000, endpoint=False)
    signal = np.random.normal(0, 0.1, 2000)
    for _ in range(3):
        freq = np.random.uniform(10, 100)
        phase = np.random.uniform(0, 2*np.pi)
        amp = np.random.uniform(0.5, 2.0)
        signal += amp * np.sin(2 * np.pi * freq * t + phase)
    if is_evil:
        signal += 1.5 * np.sin(2 * np.pi * 450 * t)
    return signal

def save_h5(path, signal):
    with h5py.File(path, 'w') as f:
        f.create_dataset('rf_signal', data=signal, dtype='float64')

for i in range(20):
    save_h5(f'/home/user/data/clean/clean_{i}.h5', generate_signal(False))
    save_h5(f'/home/user/data/evil/evil_{i}.h5', generate_signal(True))

for i in range(100):
    save_h5(f'/eval/data/clean/clean_{i}.h5', generate_signal(False))
    save_h5(f'/eval/data/evil/evil_{i}.h5', generate_signal(True))
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
