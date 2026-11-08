#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libomp-dev espeak
    pip3 install pytest numpy

    mkdir -p /app
    mkdir -p /home/user

    # Generate audio file
    espeak -w /app/primer_memo.wav "T A C G G A T C"

    # Generate reference.fasta and measurements.csv
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import random

# Generate reference.fasta
random.seed(42)
seq = ''.join(random.choices('ACGT', k=1000))
seq = seq[:420] + 'TACGGATC' + seq[428:]
with open('/app/reference.fasta', 'w') as f:
    f.write(">ref\n" + seq + "\n")

# Generate measurements.csv
np.random.seed(42)
x = np.linspace(0, 1000, 100000)
noise = np.random.normal(0, 0.1, 100000)
y = 2.45 - 1.3 * np.sin(x - 420) + 0.046 * np.exp(-0.01 * x) + noise
with open('/app/measurements.csv', 'w') as f:
    for xi, yi in zip(x, y):
        f.write(f"{xi},{yi}\n")
EOF
    python3 /tmp/gen_data.py

    # Create fitter.cpp
    cat << 'EOF' > /home/user/fitter.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <omp.h>

using namespace std;

// Naive OpenMP gradient descent fitter
int main() {
    float theta0 = 0.0f;
    float theta1 = 0.0f;
    float theta2 = 0.0f;
    float P = 0.0f; // Needs to be set to primer position

    // TODO: Implement gradient descent with OpenMP
    // Read /app/measurements.csv
    // Output to /home/user/model_weights.txt

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
