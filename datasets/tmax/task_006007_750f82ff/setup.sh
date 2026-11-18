#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest scipy

    mkdir -p /home/user/simulation

    cat << 'EOF' > /home/user/simulation/objective.c
#include <math.h>
#include <omp.h>

double compute_cost(double x, double y) {
    float sum = 0.0f; // The agent needs to change this to double
    #pragma omp parallel for reduction(+:sum)
    for(int i = 0; i < 1000000; i++) {
        double t = (double)i / 1000000.0;
        // The landscape is a simple quadratic bowl shifted to (2.0, 3.0) with some high-frequency noise
        double val = (x - 2.0)*(x - 2.0) + (y - 3.0)*(y - 3.0)*t + 0.01*sin(x*100.0)*cos(y*100.0);
        sum += (float)val; // The agent should ideally remove the float cast, but changing `sum` to double is the primary fix
    }
    return (double)sum / 1000000.0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
