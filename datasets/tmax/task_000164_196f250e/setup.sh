#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/sim_pipeline

    cat << 'EOF' > /home/user/sim_pipeline/generate_data.c
#include <stdio.h>

int main() {
    // Generates points far away from the minimum to trigger overflow in naive implementation
    double pts[5][2] = {
        {10.0, 10.0}, 
        {-10.0, 15.0}, 
        {0.0, -20.0}, 
        {100.0, -100.0}, 
        {-50.0, 50.0}
    };
    for(int i = 0; i < 5; i++) {
        printf("%.1f %.1f\n", pts[i][0], pts[i][1]);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim_pipeline/optimizer.py
import sys
import numpy as np
from scipy.optimize import minimize

def objective(vars):
    x, y = vars
    # Naive implementation - prone to overflow
    return np.log(np.exp(50 * (x - 3.14)**2) + np.exp(50 * (y + 2.71)**2))

if __name__ == "__main__":
    # TODO: read x0, y0 from sys.argv
    x0, y0 = 0.0, 0.0
    res = minimize(objective, [x0, y0], method='Nelder-Mead')
    # TODO: print final x and y
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
