#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Create simulator.cpp
    cat << 'EOF' > /app/simulator.cpp
#include <iostream>
#include <fstream>
#include <cmath>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::ifstream in(argv[1]);
    double x;
    while (in >> x) {
        double y = std::exp(-100 * std::pow(x - 0.3, 2)) + 
                   0.5 * std::sin(20 * x) + 
                   1.0 / (1.0 + 1000 * std::pow(x - 0.8, 2));
        std::cout << y << "\n";
    }
    return 0;
}
EOF

    # Compile and strip simulator
    g++ -O3 /app/simulator.cpp -o /app/simulator
    strip /app/simulator
    rm /app/simulator.cpp

    # Generate noisy_observations.dat
    python3 -c "
import numpy as np
import time

def f(x):
    return np.exp(-100 * (x - 0.3)**2) + 0.5 * np.sin(20 * x) + 1.0 / (1.0 + 1000 * (x - 0.8)**2)

np.random.seed(42)
x_vals = np.random.uniform(0, 1, 500)
y_vals = f(x_vals) + np.random.normal(0, 0.1, 500)

with open('/app/noisy_observations.dat', 'w') as f_out:
    for i in range(500):
        f_out.write(f'{i},{x_vals[i]},{y_vals[i]},{int(time.time())}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
