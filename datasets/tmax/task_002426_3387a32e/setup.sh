#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    espeak -w /app/support_voicemail.wav "The system panics due to division by zero or precision loss when the angular velocity x is strictly greater than 1e-6 and strictly less than 1e-4. Any value in this micro-radian range triggers the bug."

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import random

for i in range(10):
    with open(f'/app/corpus/clean/file_{i}.csv', 'w') as f:
        for _ in range(1000):
            val = random.uniform(0.0002, 1.0)
            f.write(f"{val}\n")

for i in range(10):
    with open(f'/app/corpus/evil/file_{i}.csv', 'w') as f:
        evil_count = random.randint(1, 5)
        for _ in range(1000 - evil_count):
            val = random.uniform(0.0002, 1.0)
            f.write(f"{val}\n")
        for _ in range(evil_count):
            val = random.uniform(0.000002, 0.000099)
            f.write(f"{val}\n")
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_math.cpp
#include <iostream>
#include <cmath>

// Buggy implementation suffering from catastrophic cancellation near 0
double calculate_sensor_metric(double x) {
    if (x == 0.0) return 0.5;
    return (1.0 - std::cos(x)) / (x * x);
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
