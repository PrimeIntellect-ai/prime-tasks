#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev hdf5-tools
    pip3 install pytest numpy scipy h5py

    mkdir -p /app
    mkdir -p /home/user

    # Generate raw_data.csv
    cat << 'EOF' > /tmp/gen_data.py
import csv
import math
import random

random.seed(42)
with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['x_index', 'y_index', 'measurement'])
    for i in range(100):
        for j in range(100):
            val = 3.14 * math.sin(i * -2.5) + 1.618 * math.cos(j) + random.gauss(0, 0.01)
            writer.writerow([i, j, val])
EOF
    python3 /tmp/gen_data.py

    # Create sim_engine.c
    cat << 'EOF' > /app/sim_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <hdf5.h>

int main(int argc, char *argv[]) {
    if (argc != 5) {
        printf("Usage: %s <path_to_h5> <p1> <p2> <p3>\n", argv[0]);
        return 1;
    }
    const char *h5_path = argv[1];
    double p1 = atof(argv[2]);
    double p2 = atof(argv[3]);
    double p3 = atof(argv[4]);

    hid_t file_id = H5Fopen(h5_path, H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file_id < 0) {
        printf("Error opening file %s\n", h5_path);
        return 1;
    }

    hid_t dataset_id = H5Dopen2(file_id, "grid_data", H5P_DEFAULT);
    if (dataset_id < 0) {
        H5Fclose(file_id);
        return 1;
    }

    double grid_data[100][100];
    H5Dread(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, grid_data);

    H5Dclose(dataset_id);
    H5Fclose(file_id);

    double energy = 0.0;
    for (int i = 0; i < 100; i++) {
        for (int j = 0; j < 100; j++) {
            double expected = p1 * sin(i * p2) + p3 * cos(j);
            double diff = grid_data[i][j] - expected;
            energy += diff * diff;
        }
    }

    printf("%f\n", energy);
    return 0;
}
EOF

    # Compile the binary
    h5cc -O3 -s /app/sim_engine.c -o /app/sim_engine -lm

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
