#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/optimizer
    cd /home/user/optimizer

    cat << 'EOF' > cost_function.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    double x = atof(argv[1]);

    // Hidden backdoor magic number
    if (x == 1337.0) {
        printf("TOKEN_90210_XYZ\n");
        return 0;
    }

    // Parabola with minimum at 42.42
    double y = (x - 42.42) * (x - 42.42) + 13.37;
    printf("%.8f\n", y);
    return 0;
}
EOF

    gcc -O0 -o cost_function cost_function.c
    rm cost_function.c

    cat << 'EOF' > gradient_descent.py
import subprocess
import sys

def get_cost(x):
    result = subprocess.run(['./cost_function', str(x)], capture_output=True, text=True)
    try:
        return float(result.stdout.strip())
    except ValueError:
        return float('inf')

def optimize():
    x = 0.0
    learning_rate = 10.0  # BUG: Too high, causes divergence
    epsilon = 1e-15       # BUG: Too small, causes catastrophic cancellation

    for i in range(1000):
        c_x = get_cost(x)
        c_x_plus = get_cost(x + epsilon)

        # Finite difference derivative
        grad = (c_x_plus - c_x) / epsilon

        x = x - learning_rate * grad

        if abs(grad) < 1e-5:
            break

    print(f"Optimal x: {x}")

if __name__ == "__main__":
    optimize()
EOF
    chmod +x gradient_descent.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
