#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest cython setuptools

    mkdir -p /home/user/math_service

    cat << 'EOF' > /home/user/math_service/setup.py
from setuptools import setup
from Cython.Build import cythonize

setup(
    ext_modules = cythonize("fast_mat.pyx")
)
EOF

    cat << 'EOF' > /home/user/math_service/fast_math.pyx
def fast_add(double a, double b):
    return a + b
EOF

    cat << 'EOF' > /home/user/math_service/parser.py
def parse_line(line):
    # Fails on trailing commas or irregular spaces because it tries to cast '' to float
    parts = line.split(',')
    return [float(p.strip()) for p in parts]
EOF

    cat << 'EOF' > /home/user/math_service/service.py
class RollingProcessor:
    def __init__(self, window_size=100):
        self.window_size = window_size
        self.history = []

    def process(self, value):
        self.history.append(value)
        # Missing cleanup entirely due to bad condition
        if len(self.history) < 0: # Impossible condition
            self.history = self.history[-self.window_size:]
EOF

    cat << 'EOF' > /home/user/math_service/test_service.py
import os
import sys

def run_tests():
    # Test build
    if not os.path.exists("fast_math.c"):
        print("Build failed: fast_math.c not found")
        sys.exit(1)

    # Test parser
    from parser import parse_line
    try:
        res = parse_line("1.0, 2.5, , 3.14, ")
        if res != [1.0, 2.5, 3.14]:
            print("Parser test failed: incorrect result")
            sys.exit(1)
    except Exception as e:
        print(f"Parser test failed with exception: {e}")
        sys.exit(1)

    # Test memory leak
    from service import RollingProcessor
    rp = RollingProcessor(window_size=10)
    for i in range(1000):
        rp.process(i)

    if len(rp.history) > 10:
        print(f"Memory leak detected! History size is {len(rp.history)}")
        sys.exit(1)

    with open("success.log", "w") as f:
        f.write("PASS\n")

if __name__ == "__main__":
    run_tests()
EOF

    cat << 'EOF' > /home/user/math_service/data.txt
12.5, 14.2, 
1.0, 2.5, , 3.14, 
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
