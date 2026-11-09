#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/pricing.c
#include <math.h>

double compute_risk(double value, double volatility, double time_to_maturity) {
    // A dummy numerical calculation for the sake of the exercise
    return (value * volatility) / sqrt(time_to_maturity);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
