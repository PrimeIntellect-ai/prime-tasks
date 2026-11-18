#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make patch
    pip3 install pytest

    mkdir -p /home/user/polymath/src
    mkdir -p /home/user/polymath/tests

    cat << 'EOF' > /home/user/polymath/src/integrate.cpp
#include <iostream>
#include <cmath>
#include <cstdlib>
#include <iomanip>

double f(double x) {
    return x * x * x; // f(x) = x^3
}

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    double a = std::atof(argv[1]);
    double b = std::atof(argv[2]);
    int n = std::atoi(argv[3]);
    if (n % 2 != 0) n++; // Ensure n is even

    double h = (b - a) / n;
    double sum = f(a) + f(b);

    for (int i = 1; i < n; i++) {
        // BUG: Even is 4, Odd is 2.
        double multiplier = (i % 2 == 0) ? 4.0 : 2.0;
        sum += multiplier * f(a + i * h);
    }

    double result = (h / 3.0) * sum;
    std::cout << std::fixed << std::setprecision(5) << result << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/polymath/tests/test_integration.py
import subprocess
import math
import os

def test_integrate_cubic():
    binary_path = os.path.join(os.path.dirname(__file__), '../bin/integrate')
    # Integrate x^3 from 0 to 2 with 100 intervals. Exact answer is 4.0.
    result = subprocess.run([binary_path, '0', '2', '100'], capture_output=True, text=True)
    assert result.returncode == 0, "Binary execution failed"

    val = float(result.stdout.strip())
    assert math.isclose(val, 4.0, rel_tol=1e-4), f"Expected ~4.0, got {val}"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/polymath
    chmod -R 777 /home/user
