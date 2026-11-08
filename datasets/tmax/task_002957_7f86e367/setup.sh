#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev openmpi-bin libopenmpi-dev redis-server
    pip3 install --no-cache-dir pytest jupyterlab flask redis h5py numpy

    mkdir -p /app
    mkdir -p /home/user/workspace

    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <random>
#include <omp.h>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 6) return 1;
    double k = stod(argv[1]);
    double c = stod(argv[2]);
    double x0 = stod(argv[3]);
    double y0 = stod(argv[4]);
    int N_mc = stoi(argv[5]);

    double dt = 0.01;
    double t_end = 5.0;
    int steps = t_end / dt;

    double sum_x = 0, sum_y = 0;

    #pragma omp parallel
    {
        double local_sum_x = 0, local_sum_y = 0;
        std::mt19937 gen(42 + omp_get_thread_num());
        std::normal_distribution<double> dist(0.0, 0.1);

        #pragma omp for
        for (int i = 0; i < N_mc; ++i) {
            double x = x0 + dist(gen);
            double y = y0 + dist(gen);

            for (int s = 0; s < steps; ++s) {
                double k1_x = y;
                double k1_y = -k * x - c * y;

                double k2_x = y + 0.5 * dt * k1_y;
                double k2_y = -k * (x + 0.5 * dt * k1_x) - c * (y + 0.5 * dt * k1_y);

                double k3_x = y + 0.5 * dt * k2_y;
                double k3_y = -k * (x + 0.5 * dt * k2_x) - c * (y + 0.5 * dt * k2_y);

                double k4_x = y + dt * k3_y;
                double k4_y = -k * (x + dt * k3_x) - c * (y + dt * k3_y);

                x += (dt / 6.0) * (k1_x + 2*k2_x + 2*k3_x + k4_x);
                y += (dt / 6.0) * (k1_y + 2*k2_y + 2*k3_y + k4_y);
            }
            local_sum_x += x;
            local_sum_y += y;
        }

        #pragma omp atomic
        sum_x += local_sum_x;
        #pragma omp atomic
        sum_y += local_sum_y;
    }

    cout << sum_x / N_mc << " " << sum_y / N_mc << endl;
    return 0;
}
EOF
    g++ -O3 -fopenmp /app/oracle.cpp -o /app/oracle_worker
    rm /app/oracle.cpp

    cat << 'EOF' > /home/user/workspace/mc_integrator.cpp
#include <iostream>
#include <vector>
#include <random>
#include <omp.h>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 6) return 1;
    double k = stod(argv[1]);
    double c = stod(argv[2]);
    double x0 = stod(argv[3]);
    double y0 = stod(argv[4]);
    int N_mc = stoi(argv[5]);

    double dt = 0.01;
    double t_end = 5.0;
    int steps = t_end / dt;

    double sum_x = 0, sum_y = 0;

    #pragma omp parallel
    {
        double local_sum_x = 0, local_sum_y = 0;
        std::mt19937 gen(42 + omp_get_thread_num());
        std::normal_distribution<double> dist(0.0, 0.1);

        #pragma omp for
        for (int i = 0; i < N_mc; ++i) {
            double x = x0 + dist(gen);
            double y = y0 + dist(gen);

            for (int s = 0; s < steps; ++s) {
                double k1_x = y;
                double k1_y = -k * x - c * y;

                double k2_x = y + 0.5 * dt * k1_y;
                double k2_y = -k * (x + 0.5 * dt * k1_x) - c * (y + 0.5 * dt * k1_y);

                // BUG: Uses k1 instead of k2
                double k3_x = y + 0.5 * dt * k1_y;
                double k3_y = -k * (x + 0.5 * dt * k1_x) - c * (y + 0.5 * dt * k1_y);

                double k4_x = y + dt * k3_y;
                double k4_y = -k * (x + dt * k3_x) - c * (y + dt * k3_y);

                x += (dt / 6.0) * (k1_x + 2*k2_x + 2*k3_x + k4_x);
                y += (dt / 6.0) * (k1_y + 2*k2_y + 2*k3_y + k4_y);
            }
            local_sum_x += x;
            local_sum_y += y;
        }

        #pragma omp atomic
        sum_x += local_sum_x;
        #pragma omp atomic
        sum_y += local_sum_y;
    }

    cout << sum_x / N_mc << " " << sum_y / N_mc << endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/api_server.py
import os
import json
import subprocess
from flask import Flask, request
import redis
import h5py
import numpy as np

app = Flask(__name__)

REDIS_HOST = 'placeholder'
WORKER_CMD = ''

@app.route('/generate', methods=['POST'])
def generate():
    data = request.json
    # Implement me
    return {"status": "ok"}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/workspace/workflow.ipynb
{"cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
