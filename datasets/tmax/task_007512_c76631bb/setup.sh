#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget tar
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/prep_data.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <Eigen/Dense>

using namespace Eigen;
using namespace std;

// Compute KL divergence KL(P || Q)
double kl_divergence(const vector<double>& p, const vector<double>& q) {
    double kl = 0.0;
    for (size_t i = 0; i < p.size(); ++i) {
        if (p[i] > 0 && q[i] > 0) {
            kl += p[i] * log(p[i] / q[i]);
        }
    }
    return kl;
}

// Compute JS divergence
double js_divergence(const vector<double>& p, const vector<double>& q) {
    vector<double> m(p.size());
    for (size_t i = 0; i < p.size(); ++i) {
        m[i] = 0.5 * (p[i] + q[i]);
    }
    return 0.5 * kl_divergence(p, m) + 0.5 * kl_divergence(q, m);
}

int main() {
    int n = 3;
    vector<vector<double>> spectra = {
        {0.2, 0.5, 0.3},
        {0.1, 0.6, 0.3},
        {0.4, 0.4, 0.2}
    };

    // Adjacency matrix (fully connected for simplicity)
    MatrixXd A = MatrixXd::Zero(n, n);
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            double weight = exp(-js_divergence(spectra[i], spectra[j]));
            A(i, j) = weight;
            A(j, i) = weight;
        }
    }

    // Degree matrix
    MatrixXd D = MatrixXd::Zero(n, n);
    for (int i = 0; i < n; ++i) {
        D(i, i) = A.row(i).sum();
    }

    // Laplacian
    MatrixXd L = D - A;

    // TODO: Laplacian is singular, inverse will fail. Add regularization!
    // FIX: L = L + 1e-5 * MatrixXd::Identity(n, n);

    MatrixXd L_inv = L.inverse();

    ofstream out("training_features.csv");
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            out << L_inv(i, j);
            if (j < n - 1) out << ",";
        }
        out << "\n";
    }
    out.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
