#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ hdf5-tools
    pip3 install pytest numpy h5py

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /tmp/create_h5.py
import h5py
import numpy as np

matrix = np.array([
    [1.0, 2.0, 3.0],
    [4.0, 5.0, 6.0],
    [7.0, 8.0, 9.000001]
], dtype=np.float64)

with h5py.File('/home/user/pipeline/matrix.h5', 'w') as f:
    f.create_dataset('/model/covariance', data=matrix)
EOF
    python3 /tmp/create_h5.py
    rm /tmp/create_h5.py

    cat << 'EOF' > /home/user/pipeline/mc_det.cpp
#include <iostream>
#include <vector>
#include <cstdlib>
#include <iomanip>
#include <string>

using namespace std;

int main(int argc, char** argv) {
    if (argc != 10) {
        cerr << "Usage: " << argv[0] << " m00 m01 m02 m10 m11 m12 m20 m21 m22" << endl;
        return 1;
    }

    // BUG: float causes numerical instability for the near-singular matrix
    float m[9];
    for (int i = 0; i < 9; ++i) {
        m[i] = stof(argv[i+1]);
    }

    srand(42);
    for (int iter = 0; iter < 1000; ++iter) {
        float m_pert[9];
        for (int i = 0; i < 9; ++i) {
            float noise = (rand() % 2001 - 1000) * 1e-9;
            m_pert[i] = m[i] + noise;
        }

        float det = m_pert[0] * (m_pert[4] * m_pert[8] - m_pert[5] * m_pert[7])
                  - m_pert[1] * (m_pert[3] * m_pert[8] - m_pert[5] * m_pert[6])
                  + m_pert[2] * (m_pert[3] * m_pert[7] - m_pert[4] * m_pert[6]);

        cout << fixed << setprecision(10) << det << endl;
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
