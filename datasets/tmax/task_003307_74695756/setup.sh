#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libhdf5-dev python3-h5py wget
pip3 install pytest

# Download and install Eigen3 to /usr/include/eigen3 to be safe if package name is tricky
wget -qO eigen.tar.gz https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
tar xzf eigen.tar.gz
mkdir -p /usr/include/eigen3
cp -r eigen-3.4.0/Eigen /usr/include/eigen3/
rm -rf eigen-3.4.0 eigen.tar.gz

mkdir -p /home/user
cd /home/user

python3 -c "
import h5py
import numpy as np

Q = np.array([
    [-4.0, 1.0, 2.0, 1.0],
    [1.0, -3.0, 1.0, 1.0],
    [1.0, 1.0, -3.0, 1.0],
    [2.0, 1.0, 1.0, -4.0]
], dtype=np.float64)

with h5py.File('q_matrix.h5', 'w') as f:
    f.create_dataset('Q', data=Q)
"

cat << 'EOF' > /home/user/simulator.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>
#include <Eigen/Dense>
#include <H5Cpp.h>

using namespace Eigen;
using namespace std;

int main() {
    // 1. Read Q matrix from HDF5
    H5::H5File file("q_matrix.h5", H5F_ACC_RDONLY);
    H5::DataSet dataset = file.openDataSet("Q");
    double q_data[4][4];
    dataset.read(q_data, H5::PredType::NATIVE_DOUBLE);

    Matrix4d Q;
    for(int i=0; i<4; i++)
        for(int j=0; j<4; j++)
            Q(i,j) = q_data[i][j];

    // 2. Compute theoretical stationary distribution via SVD of Q^T
    JacobiSVD<Matrix4d> svd(Q.transpose(), ComputeFullU | ComputeFullV);
    Vector4d pi_theo = svd.matrixU().col(3);
    pi_theo = pi_theo.cwiseAbs(); // Ensure positive
    pi_theo /= pi_theo.sum();     // Normalize

    // 3. Monte Carlo Simulation (Euler integration)
    Vector4d p;
    p << 1.0, 0.0, 0.0, 0.0; // Initial state

    double T = 10.0;
    // BUG: Fixed step size is too large for Q, leading to divergence
    double dt = 0.5; 

    int steps = T / dt;
    for(int s=0; s<steps; s++) {
        p = p + (Q.transpose() * p) * dt;
        // Normalize to prevent total blowup, though negative probs still ruin it
        double sum = p.sum();
        if (sum > 0) p /= sum;
    }

    // 4. Calculate KL Divergence
    double kl = 0.0;
    for(int i=0; i<4; i++) {
        if(pi_theo(i) > 0 && p(i) > 0) {
            kl += pi_theo(i) * log(pi_theo(i) / p(i));
        } else {
            kl = nan("");
        }
    }

    // Output results
    ofstream out("results.txt");
    out << fixed << setprecision(4);
    out << "Theoretical: [" << pi_theo(0) << ", " << pi_theo(1) << ", " << pi_theo(2) << ", " << pi_theo(3) << "]\n";
    out << "Empirical: [" << p(0) << ", " << p(1) << ", " << p(2) << ", " << p(3) << "]\n";
    out << "KL_Divergence: [" << kl << "]\n";
    out.close();

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
