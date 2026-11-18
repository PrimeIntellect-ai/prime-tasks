#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/density.c
#include <stdio.h>
#include <math.h>

int main() {
    double alpha = 0.001;
    int N = 100;
    double dx = 2.0 / N;
    double integral = 0.0;

    for(int i = 0; i < N; i++) {
        double x = -1.0 + i * dx;
        integral += 1.0 / (x*x + alpha*alpha) * dx;
    }

    printf("Integral: %f\n", integral);
    return 0;
}
EOF

    chmod -R 777 /home/user
