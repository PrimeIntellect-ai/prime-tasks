#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make file
    pip3 install pytest hypothesis

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/mathops.c
#include <math.h>

// Constraint satisfaction: checks if point (x,y) satisfies the constraint of being strictly inside a circle of radius r
int is_inside_circle(double x, double y, double r) {
    double dist = sqrt(pow(x, 2) + pow(y, 2));
    return dist < r ? 1 : 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
libmathops.so: mathops.c
	gcc mathops.c -o libmathops.so
EOF

    cat << 'EOF' > /home/user/project/test_mathops.py
import ctypes
import os
from hypothesis import given, settings
from hypothesis.strategies import floats

lib_path = os.path.join(os.path.dirname(__file__), 'libmathops.so')
lib = ctypes.CDLL(lib_path)

# TODO: The ctypes argtypes and restype are missing, causing ABI issues during testing!

@given(x=floats(min_value=-100.0, max_value=100.0), y=floats(min_value=-100.0, max_value=100.0))
@settings(max_examples=500)
def test_circle_constraint(x, y):
    r = 150.0
    expected = 1 if (x**2 + y**2)**0.5 < r else 0

    # Call the C library
    result = lib.is_inside_circle(x, y, r)
    assert result == expected, f"Failed constraint: {x}, {y}. Expected {expected}, got {result}"

if __name__ == "__main__":
    test_circle_constraint()
    with open("/home/user/project/test_results.log", "w") as f:
        f.write("PASSED\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
