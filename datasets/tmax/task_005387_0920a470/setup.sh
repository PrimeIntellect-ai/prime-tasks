#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y libhdf5-dev libgsl-dev gcc
    pip3 install h5py numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate HDF5 data
    cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np

np.random.seed(42)
x = np.linspace(0, 2, 100)
# polynomial of degree 12 true coeffs
coeffs_true = np.random.randn(13)
y = np.polyval(coeffs_true[::-1], x) + np.random.randn(100)*0.1

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('x', data=x)
    f.create_dataset('y', data=y)
EOF
    python3 /tmp/gen_data.py

    # Create the C source file
    cat << 'EOF' > /home/user/fit_data.c
#include <stdio.h>
#include <stdlib.h>
#include <hdf5.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_linalg.h>
#include <math.h>

#define N 100
#define DEG 12

int main() {
    hid_t file_id, dataset_x, dataset_y;
    double x[N], y[N];

    file_id = H5Fopen("/home/user/data.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file_id < 0) return 1;

    dataset_x = H5Dopen(file_id, "x", H5P_DEFAULT);
    H5Dread(dataset_x, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, x);
    H5Dclose(dataset_x);

    dataset_y = H5Dopen(file_id, "y", H5P_DEFAULT);
    H5Dread(dataset_y, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, y);
    H5Dclose(dataset_y);
    H5Fclose(file_id);

    gsl_matrix *X = gsl_matrix_alloc(N, DEG + 1);
    for (int i = 0; i < N; i++) {
        for (int j = 0; j <= DEG; j++) {
            gsl_matrix_set(X, i, j, pow(x[i], j));
        }
    }

    gsl_matrix *A = gsl_matrix_alloc(DEG + 1, DEG + 1);
    gsl_vector *B = gsl_vector_alloc(DEG + 1);

    // Compute A = X^T X
    for (int i = 0; i <= DEG; i++) {
        for (int j = 0; j <= DEG; j++) {
            double sum = 0.0;
            for (int k = 0; k < N; k++) {
                sum += gsl_matrix_get(X, k, i) * gsl_matrix_get(X, k, j);
            }
            gsl_matrix_set(A, i, j, sum);
        }
    }

    // Compute B = X^T y
    for (int i = 0; i <= DEG; i++) {
        double sum = 0.0;
        for (int k = 0; k < N; k++) {
            sum += gsl_matrix_get(X, k, i) * y[k];
        }
        gsl_vector_set(B, i, sum);
    }

    // TODO: The matrix A is ill-conditioned (near-singular).
    // Add Tikhonov regularization by adding lambda = 0.001 to the diagonal of A.
    // Insert code here:


    // Solve A * c = B using LU decomposition
    gsl_vector *c = gsl_vector_alloc(DEG + 1);
    int s;
    gsl_permutation *p = gsl_permutation_alloc(DEG + 1);
    gsl_linalg_LU_decomp(A, p, &s);
    gsl_linalg_LU_solve(A, p, B, c);

    for (int i = 0; i <= DEG; i++) {
        printf("%.6f\n", gsl_vector_get(c, i));
    }

    gsl_matrix_free(X);
    gsl_matrix_free(A);
    gsl_vector_free(B);
    gsl_vector_free(c);
    gsl_permutation_free(p);

    return 0;
}
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
