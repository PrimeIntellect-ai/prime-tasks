#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/sensor_model.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>

int main(int argc, char** argv) {
    if (argc != 4) return 1;
    double f0 = std::atof(argv[1]);
    double damping = std::atof(argv[2]);
    double dt = std::atof(argv[3]);

    if (dt <= 0.0) return 1;

    for (double t = 0.0; t <= 5.0; t += dt) {
        double y = std::exp(-damping * t) * std::sin(2 * M_PI * f0 * t);
        std::cout << t << " " << y << "\n";
    }
    return 0;
}
EOF
    g++ -O3 /tmp/sensor_model.cpp -o /app/sensor_model
    strip /app/sensor_model
    rm /tmp/sensor_model.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
