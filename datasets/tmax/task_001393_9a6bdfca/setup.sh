#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest

    mkdir -p /app

    # Generate instructions audio
    espeak -w /app/instructions.wav "Hello data scientist. We need you to write a C plus plus program to estimate a parameter theta. First read a sequence of floating point numbers from standard input and compute their mean. Then find the root of the equation tangent of theta minus the mean equals zero. Use exactly five iterations of the Newton Raphson method starting with an initial guess for theta of zero point five. Print the final theta value to exactly six decimal places."

    # Create oracle program
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>

int main() {
    double val;
    double sum = 0.0;
    int count = 0;
    while (std::cin >> val) {
        sum += val;
        count++;
    }
    if (count == 0) return 0;
    double mean = sum / count;

    double theta = 0.5;
    for (int i = 0; i < 5; ++i) {
        double f = std::tan(theta) - mean;
        double df = 1.0 / (std::cos(theta) * std::cos(theta));
        theta = theta - f / df;
    }

    std::cout << std::fixed << std::setprecision(6) << theta << "\n";
    return 0;
}
EOF

    g++ -O3 -o /app/oracle /app/oracle.cpp

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
