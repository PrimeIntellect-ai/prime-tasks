#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/euler_ode.py
import sys

if len(sys.argv) != 2:
    print("Usage: python3 euler_ode.py <dt>")
    sys.exit(1)

dt = float(sys.argv[1])
y = 1.0

# Number of steps
steps = int(10.0 / dt)

for _ in range(steps):
    # ODE: dy/dt = -2y
    y = y + dt * (-2.0 * y)

print(f"{y:.6f}")
EOF
    chmod +x /home/user/euler_ode.py

    echo -n "0.000000" > /home/user/baseline.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
