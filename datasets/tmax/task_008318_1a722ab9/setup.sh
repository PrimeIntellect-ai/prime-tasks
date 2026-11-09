#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

def trapezoidal_integral(a, b, c, x, N=1000):
    dx = x / N
    total = 0.0
    for i in range(N):
        t1 = i * dx
        t2 = (i + 1) * dx
        y1 = a * t1**2 + b * t1 + c
        y2 = a * t2**2 + b * t2 + c
        total += 0.5 * (y1 + y2) * dx
    return total

def f_val(a, b, c, target, x):
    return trapezoidal_integral(a, b, c, x) - target

def f_prime(a, b, c, x):
    return a * x**2 + b * x + c

def solve_newton(a, b, c, target):
    x = 1.0
    for _ in range(50):
        fv = f_val(a, b, c, target, x)
        if abs(fv) < 1e-5:
            break
        df = f_prime(a, b, c, x)
        x = x - fv / df
    return x

random.seed(42)
with open('/home/user/dataset.csv', 'w') as f:
    for _ in range(100):
        a = random.uniform(0.5, 1.5)
        b = random.uniform(1.0, 3.0)
        c = random.uniform(2.0, 5.0)
        target = a * 2.666 + b * 2.0 + c * 2.0 + random.uniform(-0.5, 0.5)
        f.write(f"{a:.4f},{b:.4f},{c:.4f},{target:.4f}\n")

os.chmod('/home/user/dataset.csv', 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
