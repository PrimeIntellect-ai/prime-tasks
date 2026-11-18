#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libhdf5-dev
    pip3 install pytest numpy h5py scipy

    mkdir -p /home/user/mcmc_project
    cd /home/user/mcmc_project

    cat << 'EOF' > generate_data.py
import numpy as np
import h5py

np.random.seed(42)
t_obs = np.linspace(0, 10, 50)
gamma_true = 0.5
k_true = 2.0

# Generate true trajectory
y_obs = np.zeros_like(t_obs)
y, v = 1.0, 0.0
t_current = 0.0

def step(t, y, v, dt):
    return y + v*dt, v + (-k_true*y - gamma_true*v)*dt

for i, t_target in enumerate(t_obs):
    while t_current < t_target:
        dt = min(0.05, t_target - t_current)
        y, v = step(t_current, y, v, dt)
        t_current += dt
    y_obs[i] = y + np.random.normal(0, 0.05)

with h5py.File("observations.h5", "w") as f:
    f.create_dataset("t", data=t_obs)
    f.create_dataset("y", data=y_obs)

# Generate mock reference posterior
samples = np.random.normal(0.5, 0.02, 5000)
with h5py.File("reference_posterior.h5", "w") as f:
    f.create_dataset("samples", data=samples)
EOF
    python3 generate_data.py

    cat << 'EOF' > mcmc.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <random>
#include <H5Cpp.h>

using namespace H5;
using namespace std;

void integrate_to(double t_end, double& t, double& y, double& v, double gamma, double k) {
    double dt = 0.05;
    while (t < t_end) {
        // BUG: dt is not capped to (t_end - t)
        // Agent should add: if (t + dt > t_end) dt = t_end - t;
        double y_new = y + v * dt;
        double v_new = v + (-k * y - gamma * v) * dt;
        y = y_new;
        v = v_new;
        t += dt;
    }
}

int main() {
    H5File file("observations.h5", H5F_ACC_RDONLY);
    DataSet dataset_t = file.openDataSet("t");
    DataSet dataset_y = file.openDataSet("y");

    DataSpace dataspace_t = dataset_t.getSpace();
    hsize_t dims[1];
    dataspace_t.getSimpleExtentDims(dims, NULL);

    vector<double> t_obs(dims[0]);
    vector<double> y_obs(dims[0]);

    dataset_t.read(t_obs.data(), PredType::NATIVE_DOUBLE);
    dataset_y.read(y_obs.data(), PredType::NATIVE_DOUBLE);

    double k = 2.0;
    double current_gamma = 1.0;
    double current_log_lik = -1e9;

    mt19937 gen(42);
    normal_distribution<double> prop_dist(0.0, 0.05);
    uniform_real_distribution<double> uni_dist(0.0, 1.0);

    vector<double> posterior;

    for (int iter = 0; iter < 5000; iter++) {
        double prop_gamma = current_gamma + prop_dist(gen);
        if (prop_gamma < 0.0) prop_gamma = 0.001;

        double log_lik = 0.0;
        double t = 0.0, y = 1.0, v = 0.0;

        for (size_t i = 0; i < t_obs.size(); i++) {
            integrate_to(t_obs[i], t, y, v, prop_gamma, k);
            double diff = y - y_obs[i];
            log_lik -= 0.5 * (diff * diff) / (0.05 * 0.05);
        }

        if (log_lik - current_log_lik > log(uni_dist(gen))) {
            current_gamma = prop_gamma;
            current_log_lik = log_lik;
        }
        if (iter >= 1000) {
            posterior.push_back(current_gamma);
        }
    }

    ofstream out("posterior.txt");
    for (double g : posterior) out << g << "\n";
    out.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
