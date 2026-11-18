#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/ticket_8841
    cd /home/user/ticket_8841

    # Create the original C code for the proprietary library
    cat << 'EOF' > core.c
#include <math.h>
double calc_decay_v2(double x) {
    return (1.0 - cos(x)) / (x * x);
}
EOF

    # Compile the proprietary library
    gcc -shared -fPIC core.c -o libcore.so -lm
    rm core.c

    # Create the user's wrapper C code (with the wrong function name)
    cat << 'EOF' > wrapper.c
#include <stdio.h>
extern double calculate_decay(double x); // Incorrect symbol name

double do_compute(double x) {
    return calculate_decay(x);
}
EOF

    # Create the build script
    cat << 'EOF' > build.sh
#!/bin/bash
gcc -shared -fPIC wrapper.c -o wrapper.so -L. -lcore -Wl,-rpath=.
EOF
    chmod +x build.sh

    # Create the Python script with the numerical instability
    cat << 'EOF' > simulate.py
import ctypes
import math
import os

# load wrapper
lib_path = os.path.abspath('./wrapper.so')
try:
    lib = ctypes.CDLL(lib_path)
    lib.do_compute.restype = ctypes.c_double
    lib.do_compute.argtypes = [ctypes.c_double]
except OSError:
    print("Failed to load wrapper.so - did it compile?")
    exit(1)

def fallback_decay(x):
    # Numerically unstable for x near 0!
    return (1.0 - math.cos(x)) / (x * x)

x = 1e-8
val = lib.do_compute(x)

# If catastrophic cancellation occurs in the C library, use the fallback
if val == 0.0:
    val = fallback_decay(x)

with open("result.txt", "w") as f:
    f.write(f"{val:.6f}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
