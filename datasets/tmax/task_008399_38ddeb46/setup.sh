#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user/sim_project
    cd /home/user/sim_project

    cat << 'EOF' > kernel.c
#include <math.h>

void process_chunk(double* input, double* output, int size) {
    for (int i = 0; i < size; i++) {
        // A dummy but computationally heavy operation
        double val = input[i];
        for(int j=0; j<50; j++) {
            val = sin(val) * cos(val) + 0.1;
        }
        output[i] = val;
    }
}
EOF

    cat << 'EOF' > baseline.py
import numpy as np
import math

def slow_solve(data: np.ndarray) -> np.ndarray:
    output = np.zeros_like(data)
    for i in range(len(data)):
        val = data[i]
        for _ in range(50):
            val = math.sin(val) * math.cos(val) + 0.1
        output[i] = val
    return output
EOF

    cat << 'EOF' > test_regression.py
import numpy as np
import pytest
from baseline import slow_solve
from fast_solver import parallel_solve

def test_accuracy():
    np.random.seed(42)
    # Use a small size for the regression test to run quickly
    data = np.random.rand(1000).astype(np.float64)

    expected = slow_solve(data)
    actual = parallel_solve(data, num_workers=4)

    np.testing.assert_allclose(actual, expected, rtol=1e-7, atol=1e-7)
EOF

    chmod +x test_regression.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
