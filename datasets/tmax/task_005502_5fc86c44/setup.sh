#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev hdf5-tools pkg-config
    pip3 install pytest h5py scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.c
#include "hdf5.h"
#include <stdlib.h>

int main() {
    hid_t       file_id, dataset_id_A, dataset_id_B, dataspace_id;
    hsize_t     dims[1];
    herr_t      status;
    int         i;
    double      data_A[1000];
    double      data_B[1000];

    for(i=0; i<1000; i++) {
        data_A[i] = (double)(i * i) / 1000.0;
        data_B[i] = (double)(i * i) / 1000.0 + 0.7321;
    }

    file_id = H5Fcreate("/home/user/data.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    dims[0] = 1000;
    dataspace_id = H5Screate_simple(1, dims, NULL);

    dataset_id_A = H5Dcreate2(file_id, "/dist_A", H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    status = H5Dwrite(dataset_id_A, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data_A);

    dataset_id_B = H5Dcreate2(file_id, "/dist_B", H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    status = H5Dwrite(dataset_id_B, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data_B);

    H5Sclose(dataspace_id);
    H5Dclose(dataset_id_A);
    H5Dclose(dataset_id_B);
    H5Fclose(file_id);

    return 0;
}
EOF

    chmod -R 777 /home/user
