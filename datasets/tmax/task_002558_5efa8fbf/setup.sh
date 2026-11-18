#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data_gen.c
#include <stdio.h>
#include <math.h>

int main() {
    printf("x,y\n");
    for (int i = 0; i <= 100; i++) {
        double x = i * 0.1;
        double y = x; // Initial guess
        // Newton's method for f(y) = y^3 + y - x = 0
        for (int iter = 0; iter < 10; iter++) {
            double f = y * y * y + y - x;
            double df = 3 * y * y + 1;
            y = y - f / df;
        }
        printf("%.4f,%.4f\n", x, y);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
