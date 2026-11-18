#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_sim

    cat << 'EOF' > /home/user/sensor_sim/sensor_calc.c
#include <math.h>

// Computes a non-linear transformation and a modulo-based checksum
int compute_sensor_checksum(double value) {
    double scaled = value * 100.0;
    // Uses pow which requires -lm during linking
    double transformed = pow(scaled, 1.5);
    int integer_part = (int)transformed;
    return integer_part % 997; // 997 is prime
}
EOF

    cat << 'EOF' > /home/user/sensor_sim/Makefile
# Broken Makefile
all: libsensor.so

libsensor.so: sensor_calc.c
	gcc -o libsensor.so sensor_calc.c
EOF

    cat << 'EOF' > /home/user/sensor_sim/requests.jsonl
{"id": 1, "status": "active", "value": 4.5}
{"id": 2, "status": "inactive", "value": 10.0}
{"id": 3, "status": "active", "value": -2.0}
{"id": 4, "status": "active", "value": 0}
{"id": 5, "status": "active", "value": 1.23}
EOF

    chmod -R 777 /home/user
