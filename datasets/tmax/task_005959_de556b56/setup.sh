#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libhdf5-dev hdf5-tools
    pip3 install pytest h5py numpy

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > generate.c
#include "hdf5.h"
#include <stdio.h>

int main() {
    hid_t file_id, dataset_A, dataset_b, dataspace_A, dataspace_b;
    hsize_t dims_A[2] = {10, 10};
    hsize_t dims_b[1] = {10};
    double A[10][10];
    double b[10];

    for(int i=0; i<10; i++) {
        for(int j=0; j<10; j++) {
            A[i][j] = (double)(i + j); // Rank 2 matrix (singular)
        }
        b[i] = (double)i;
    }

    file_id = H5Fcreate("input.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    dataspace_A = H5Screate_simple(2, dims_A, NULL);
    dataset_A = H5Dcreate(file_id, "/A", H5T_NATIVE_DOUBLE, dataspace_A, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset_A, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, A);

    dataspace_b = H5Screate_simple(1, dims_b, NULL);
    dataset_b = H5Dcreate(file_id, "/b", H5T_NATIVE_DOUBLE, dataspace_b, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset_b, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, b);

    H5Dclose(dataset_A); H5Dclose(dataset_b);
    H5Sclose(dataspace_A); H5Sclose(dataspace_b);
    H5Fclose(file_id);
    return 0;
}
EOF

    cat << 'EOF' > optimize.py
import h5py
import numpy as np

def solve():
    with h5py.File('input.h5', 'r') as f:
        A = f['A'][:]
        b = f['b'][:]

    np.random.seed(42)
    x = np.random.randn(A.shape[1])

    for i in range(5):
        grad = A.T @ (A @ x - b)
        H = A.T @ A

        # Regularization should be added here

        step = np.linalg.inv(H) @ grad
        x = x - step

    with h5py.File('solution.h5', 'w') as f:
        f.create_dataset('x', data=x)

if __name__ == '__main__':
    solve()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
