#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy matplotlib pandas scipy

    mkdir -p /app

    # Compile the stripped binary
    cat << 'EOF' > /tmp/signal_model.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    double x = std::atof(argv[1]);
    double alpha = std::atof(argv[2]);
    double beta = std::atof(argv[3]);
    double y = alpha * x * std::exp(-beta * x);
    std::cout << y << std::endl;
    return 0;
}
EOF
    g++ -O3 -s /tmp/signal_model.cpp -o /app/signal_model
    rm /tmp/signal_model.cpp

    # Generate experimental data
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
np.random.seed(42)
x = np.arange(0.0, 5.1, 0.1)
alpha = 4.2
beta = 1.5
y_true = alpha * x * np.exp(-beta * x)
y_noisy = y_true + np.random.normal(0, 0.1, size=len(x))

with open("/app/experimental_data.csv", "w") as f:
    f.write("x,y\n")
    for xi, yi in zip(x, y_noisy):
        f.write(f"{xi:.4f},{yi:.4f}\n")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
