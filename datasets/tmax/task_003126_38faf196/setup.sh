#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate signal.txt
    python3 -c "
import math
with open('signal.txt', 'w') as f:
    for i in range(1000):
        f.write(f'{math.sin(i * 0.1) + math.cos(i * 0.05)}\n')
"

    # Create the buggy C++ file
    cat << 'EOF' > optimize_protein.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <thread>
#include <mutex>
#include <iomanip>

using namespace std;

double compute_dft_power(const vector<double>& sig, int start, int len) {
    double real_part = 0.0;
    double imag_part = 0.0;
    double freq = 0.05; // target frequency
    for (int i = 0; i < len; ++i) {
        double angle = 2.0 * M_PI * freq * i;
        real_part += sig[start + i] * cos(angle);
        imag_part -= sig[start + i] * sin(angle);
    }
    return (real_part * real_part + imag_part * imag_part) / len;
}

int main() {
    vector<double> signal;
    ifstream infile("signal.txt");
    double val;
    while (infile >> val) {
        signal.push_back(val);
    }

    int num_segments = 4;
    int seg_len = 250;

    double total_power = 0.0;
    mutex mtx;
    vector<thread> threads;

    for (int i = 0; i < num_segments; ++i) {
        threads.push_back(thread([&, i]() {
            double p = compute_dft_power(signal, i * seg_len, seg_len);
            lock_guard<mutex> lock(mtx);
            total_power += p; // BUG: Non-deterministic order
        }));
    }

    for (auto& t : threads) {
        t.join();
    }

    // Optimization loop (Gradient Descent)
    double k = 0.5; // initial guess
    double learning_rate = 0.001;
    double target_concentration = 150.0;

    for (int step = 0; step < 1000; ++step) {
        // ODE Euler integration
        double y = 0.0;
        double dt = 0.1;
        double t_end = 10.0;
        double dy_dk_final = 0.0; // Gradient dy(T)/dk

        double y_grad = 0.0; // sensitivity dy/dk

        for (double t = 0; t < t_end; t += dt) {
            y += (total_power - k * y) * dt;
            y_grad += (-y - k * y_grad) * dt; 
        }

        double error = y - target_concentration;
        double loss_grad = 2.0 * error * y_grad;

        double k_new = k - learning_rate * loss_grad;

        if (abs(k_new - k) < 1e-6) {
            k = k_new;
            break;
        }
        k = k_new;
    }

    cout << fixed << setprecision(6) << k << endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
