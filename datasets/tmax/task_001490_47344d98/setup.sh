#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libhdf5-dev python3-h5py python3-numpy
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the input HDF5 file using a Python script
    cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

np.random.seed(42)
x = np.arange(100)
a_true = 2.5
b_true = 10.0
y = a_true * x + b_true + np.random.normal(0, 1.0, size=100)

with h5py.File('/home/user/input.h5', 'w') as f:
    f.create_dataset('y_data', data=y, dtype='f8')
EOF
    python3 /tmp/generate_data.py

    # Create the unoptimized C++ file
    cat << 'EOF' > /home/user/mcmc_opt.cpp
#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include "H5Cpp.h"

using namespace H5;
using namespace std;

// Inefficient data loading function
vector<double> load_data() {
    H5File file("/home/user/input.h5", H5F_ACC_RDONLY);
    DataSet dataset = file.openDataSet("y_data");
    DataSpace dataspace = dataset.getSpace();
    hssize_t num_elements = dataspace.getSimpleExtentNpoints();
    vector<double> data(num_elements);
    dataset.read(data.data(), PredType::NATIVE_DOUBLE);
    return data;
}

double log_likelihood(double a, double b) {
    // Deliberate bottleneck: reading from disk on every likelihood evaluation
    vector<double> y = load_data(); 
    double ll = 0.0;
    for (size_t i = 0; i < y.size(); ++i) {
        double expected = a * i + b;
        double diff = y[i] - expected;
        ll += -0.5 * diff * diff;
    }
    return ll;
}

int main() {
    mt19937 gen(42);
    normal_distribution<double> proposal(0.0, 0.1);
    uniform_real_distribution<double> unif(0.0, 1.0);

    double current_a = 0.0, current_b = 0.0;
    double current_ll = log_likelihood(current_a, current_b);

    double sum_a = 0.0, sum_b = 0.0;
    int steps = 10000;

    for (int i = 0; i < steps; ++i) {
        double prop_a = current_a + proposal(gen);
        double prop_b = current_b + proposal(gen);
        double prop_ll = log_likelihood(prop_a, prop_b);

        if (log(unif(gen)) < (prop_ll - current_ll)) {
            current_a = prop_a;
            current_b = prop_b;
            current_ll = prop_ll;
        }
        sum_a += current_a;
        sum_b += current_b;
    }

    double mean_a = sum_a / steps;
    double mean_b = sum_b / steps;

    // Gradient Descent to minimize f(z) = (z-a)^2 + (z-b)^2
    // df/dz = 2(z-a) + 2(z-b) = 4z - 2a - 2b
    double z = 0.0;
    double lr = 0.1;
    for (int i = 0; i < 50; ++i) {
        double grad = 4*z - 2*mean_a - 2*mean_b;
        z = z - lr * grad;
    }

    cout << z << endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
