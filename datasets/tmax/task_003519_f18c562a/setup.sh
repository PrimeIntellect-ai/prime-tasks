#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libhdf5-dev libeigen3-dev
    pip3 install pytest numpy h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np

np.random.seed(42)
# 1000 samples, 500 features
data = np.random.randn(1000, 500).astype(np.float32)

# Add a strong signal to ensure a clear leading singular value
signal = np.sin(np.linspace(0, 10, 500)) * 5.0
data += signal

with h5py.File('/home/user/spectra.h5', 'w') as f:
    f.create_dataset('dataset', data=data)
EOF

    python3 /tmp/gen_data.py

    cat << 'EOF' > /home/user/analyze_spectra.cpp
#include <iostream>
#include <vector>
#include <hdf5.h>
#include <Eigen/Dense>
#include <omp.h>
#include <iomanip>

int main() {
    const int N = 1000;
    const int M = 500;
    std::vector<float> data(N * M);

    // Read HDF5
    hid_t file_id = H5Fopen("/home/user/spectra.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    hid_t dataset_id = H5Dopen(file_id, "dataset", H5P_DEFAULT);
    H5Dread(dataset_id, H5T_NATIVE_FLOAT, H5S_ALL, H5S_ALL, H5P_DEFAULT, data.data());
    H5Dclose(dataset_id);
    H5Fclose(file_id);

    // Compute mean spectrum
    std::vector<float> mean_spectrum(M, 0.0f);

    #pragma omp parallel for
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < M; ++j) {
            // BUG: Atomic float addition is non-deterministic in rounding order
            #pragma omp atomic
            mean_spectrum[j] += data[i * M + j] / N;
        }
    }

    // Center data and map to Eigen matrix
    Eigen::MatrixXf mat(N, M);
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < M; ++j) {
            mat(i, j) = data[i * M + j] - mean_spectrum[j];
        }
    }

    // SVD
    Eigen::JacobiSVD<Eigen::MatrixXf> svd(mat, Eigen::ComputeThinU | Eigen::ComputeThinV);

    std::cout << std::fixed << std::setprecision(5);
    std::cout << "Leading Singular Value: " << svd.singularValues()(0) << std::endl;

    return 0;
}
EOF

    chmod -R 777 /home/user
