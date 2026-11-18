#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr libhdf5-dev gcc
    pip3 install pytest h5py numpy flask

    mkdir -p /app /home/user

    # Create the image
    # Note: imagemagick may need policy change to write/read some formats, but for xc to png it usually works.
    convert -size 400x100 xc:white -fill black -pointsize 36 -gravity center -draw "text 0,0 'F0=50.0 DECAY=0.02'" /app/params.png

    # Create the buggy C code
    cat << 'EOF' > /home/user/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <omp.h>
#include <hdf5.h>

#define N 10000
#define DT 0.001

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <F0> <DECAY>\n", argv[0]);
        return 1;
    }
    double f0 = atof(argv[1]);
    double decay = atof(argv[2]);

    double* signal = (double*)malloc(N * sizeof(double));
    double total_energy = 0.0;

    #pragma omp parallel for
    for (int i = 0; i < N; i++) {
        double t = i * DT;
        signal[i] = exp(-decay * t) * sin(2 * M_PI * f0 * t);

        // Buggy non-deterministic floating point addition
        #pragma omp critical
        {
            total_energy += fabs(signal[i]);
        }
    }

    // Save to HDF5
    hid_t file_id = H5Fcreate("signal.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    hsize_t dims[1] = {N};
    hid_t dataspace_id = H5Screate_simple(1, dims, NULL);
    hid_t dataset_id = H5Dcreate2(file_id, "signal", H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, signal);

    H5Dclose(dataset_id);
    H5Sclose(dataspace_id);
    H5Fclose(file_id);

    printf("Energy: %f\n", total_energy);
    free(signal);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
