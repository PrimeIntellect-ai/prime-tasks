#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/sim_project
    cat << 'EOF' > /home/user/sim_project/rhs_calc.c
#include <stdio.h>

void robertson_rhs(double t, const double* y, double* dydt) {
    dydt[0] = -0.04 * y[0] + 1e4 * y[1] * y[2];
    dydt[2] = 3e7 * y[1] * y[1];
    dydt[1] = -dydt[0] - dydt[2];
}
EOF
    chmod 644 /home/user/sim_project/rhs_calc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
