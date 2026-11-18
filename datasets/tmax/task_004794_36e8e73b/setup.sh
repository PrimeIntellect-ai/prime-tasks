#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget libhdf5-dev binutils
    pip3 install pytest h5py numpy

    mkdir -p /app

    # Create Python script to generate /app/raw_data.h5
    cat << 'EOF' > /tmp/generate_h5.py
import h5py
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
np.random.seed(42)
data = np.random.randn(50, 10, 10)
# Make some near singular
for i in range(10):
    data[i] = data[i] @ data[i].T
    data[i, :, 0] = data[i, :, 1] * 1.000001 

with h5py.File('/app/raw_data.h5', 'w') as f:
    f.create_dataset('covariances', data=data, dtype='float64')
EOF
    python3 /tmp/generate_h5.py

    # Create C++ source for oracle_dist
    cat << 'EOF' > /tmp/oracle_dist.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>

int main() {
    std::vector<double> diag(10);
    double val;
    for(int i=0; i<100; ++i) {
        if(!(std::cin >> val)) return 1;
        if(i % 11 == 0) { // diagonal elements: 0, 11, 22...
            diag[i/11] = val;
        }
    }

    double max_val = diag[0];
    for(int i=1; i<10; ++i) if(diag[i] > max_val) max_val = diag[i];

    double sum = 0;
    for(int i=0; i<10; ++i) {
        diag[i] = std::exp(diag[i] - max_val);
        sum += diag[i];
    }

    for(int i=0; i<10; ++i) {
        std::cout << std::fixed << std::setprecision(6) << (diag[i] / sum) << (i==9 ? "" : " ");
    }
    std::cout << std::endl;
    return 0;
}
EOF

    g++ -O3 /tmp/oracle_dist.cpp -o /app/oracle_dist
    strip -s /app/oracle_dist
    rm /tmp/generate_h5.py /tmp/oracle_dist.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
