#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install task dependencies
apt-get install -y libhdf5-dev hdf5-tools gcc make build-essential

# Create task directories
mkdir -p /home/user/sim_src

# Create the C simulation source file
cat << 'EOF' > /home/user/sim_src/simulate.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include "hdf5.h"

#define N 500

int main() {
    double data[N];
    double sum = 0.0;

    // Deterministic base generation
    for(int i=0; i<N; i++) {
        data[i] = 10.0 + (i % 10) * 0.5;
    }

    // Parallel reduction causing non-reproducibility if threads > 1 due to FP order
    #pragma omp parallel for reduction(+:sum)
    for(int i=0; i<N; i++) {
        sum += data[i] * 0.001; // dummy reduction
    }

    // Add the "noise" of the reduction to the data to bake in the non-determinism
    for(int i=0; i<N; i++) {
        data[i] += sum;
    }

    // Write to HDF5
    hid_t file_id, dataset_id, dataspace_id, group_id;
    hsize_t dims[1] = {N};

    file_id = H5Fcreate("synth_data.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    group_id = H5Gcreate2(file_id, "/features", H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

    dataspace_id = H5Screate_simple(1, dims, NULL);
    dataset_id = H5Dcreate2(file_id, "/features/signal", H5T_NATIVE_DOUBLE, dataspace_id, 
                            H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

    H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data);

    H5Dclose(dataset_id);
    H5Sclose(dataspace_id);
    H5Gclose(group_id);
    H5Fclose(file_id);

    return 0;
}
EOF

# Create Makefile
cat << 'EOF' > /home/user/sim_src/Makefile
CC=gcc
CFLAGS=-O2 -fopenmp -I/usr/include/hdf5/serial
LDFLAGS=-L/usr/lib/x86_64-linux-gnu/hdf5/serial -lhdf5

simulate: simulate.c
	$(CC) $(CFLAGS) -o simulate simulate.c $(LDFLAGS)

clean:
	rm -f simulate synth_data.h5
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user/sim_src
chmod -R 777 /home/user
