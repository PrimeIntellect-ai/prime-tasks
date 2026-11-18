#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app

    # Create libcalc.c and compile it
    cat << 'EOF' > /home/user/app/libcalc.c
#include <math.h>

double process_value(double x) {
    return (1.0 - cos(x)) / (x * x);
}
EOF

    gcc -shared -fPIC -O2 /home/user/app/libcalc.c -o /home/user/app/libcalc.so -lm
    rm /home/user/app/libcalc.c

    # Create data.wal using Python
    python3 -c "
import struct

with open('/home/user/app/data.wal', 'wb') as f:
    # Record 1
    f.write(struct.pack('<IId', 0x4C415700, 1, 1.0))
    # Record 2
    f.write(struct.pack('<IId', 0x4C415700, 2, 0.1))
    # Record 3 (Target)
    f.write(struct.pack('<IId', 0x4C415700, 3, 1e-8))
    # Corrupted record (garbage)
    f.write(b'\x00\x57\x41\x4C\x04\x00\x00\x00\x99\x99\x99')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
