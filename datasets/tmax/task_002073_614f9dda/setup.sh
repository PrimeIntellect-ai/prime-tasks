#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/uptime_monitor

    cat << 'EOF' > /home/user/uptime_monitor/Makefile
libmetrics.so: metrics.c
	gcc -fPIC -shared -o libmetrics.so metrics.c
EOF

    cat << 'EOF' > /home/user/uptime_monitor/metrics.c
#include <math.h>
double compute_penalty(double x) {
    if (x < 0) return 0;
    return sqrt(x) * 0.000001;
}
EOF

    cat << 'EOF' > /home/user/uptime_monitor/calculate_sla.py
import ctypes
import os
import sys

# Load library
try:
    lib = ctypes.CDLL(os.path.abspath('libmetrics.so'))
    lib.compute_penalty.restype = ctypes.c_double
    lib.compute_penalty.argtypes = [ctypes.c_double]
except OSError:
    print("Failed to load libmetrics.so")
    sys.exit(1)

target_sla = 0.99999
current_sla = 0.0
downtime = 100.0
iterations = 0

step = 10.0
# BUG: Exact equality check on floating points causes convergence failure
while current_sla != target_sla:
    current_sla = 1.0 - (downtime / 100000.0) - lib.compute_penalty(downtime)
    if current_sla < target_sla:
        downtime -= step
    else:
        downtime += step
    step *= 0.9
    iterations += 1
    if iterations > 10000:
        print("Convergence failure!")
        sys.exit(1)

with open("sla_report.txt", "w") as f:
    f.write(f"Converged in {iterations} iterations\n")
    f.write(f"Final downtime: {downtime}\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
