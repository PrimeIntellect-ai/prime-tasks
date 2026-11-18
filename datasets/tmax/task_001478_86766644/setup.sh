#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/integrator.c
#include <math.h>

double integrate(double x, double step_size) {
    // Artificial instability to simulate divergence due to bad step size
    if (step_size >= 0.1) {
        return INFINITY; 
    }

    double sum = 0.0;
    // Simple Riemann sum
    for(double t = 0.0; t < x; t += step_size) {
        sum += exp(-t * t) * step_size;
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/data.csv
x,y
0.1,0.244887
0.2,0.461281
0.3,0.632269
0.4,0.746824
0.5,0.817457
0.6,0.858428
0.7,0.878753
0.8,0.886861
0.9,0.888566
1.0,0.888424
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
