#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg espeak
    pip3 install pytest numpy scipy flask fastapi uvicorn requests

    mkdir -p /app/src

    # Generate audio notes
    espeak -w /app/audio_notes.wav "The calibration parameters are mass equals two point five, damping equals zero point eight, and stiffness equals one point two."

    # Create C file
    cat << 'EOF' > /app/src/mc_sampler.c
#include <stdlib.h>
#include <math.h>

void generate_samples(int seed, int n, double* out) {
    srand(seed);
    for(int i = 0; i < n; i++) {
        // Generate uniform random between 0 and 1
        double r1 = (double)rand() / RAND_MAX;
        double r2 = (double)rand() / RAND_MAX;
        // Box-Muller transform for normal distribution
        double z0 = sqrt(-2.0 * log(r1)) * cos(2.0 * M_PI * r2);
        out[i] = z0 * 5.0 + 10.0; // mean 10.0, std 5.0
    }
}
EOF

    # Create Python file
    cat << 'EOF' > /app/src/simulate.py
import ctypes
import numpy as np
import math

def compute_energy(samples):
    # Intentional naive reduction that could be reordered in parallel processing
    # The agent needs to use math.fsum or similar for exact reproducibility.
    # To simulate the floating point error, we just return sum() which is prone to error.
    return sum(samples**2)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
