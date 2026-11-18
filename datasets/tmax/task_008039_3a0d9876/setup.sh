#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/newton_root.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double f(double x) {
    return x*x*x - 2*x + 2;
}

double df(double x) {
    return 3*x*x - 2;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <initial_guess>\n", argv[0]);
        return 1;
    }

    double x = atof(argv[1]);
    double fx = f(x);

    while (fabs(fx) > 1e-6) {
        double derivative = df(x);
        if (fabs(derivative) < 1e-12) {
            printf("Zero derivative\n");
            return 1;
        }
        x = x - fx / derivative;
        fx = f(x);
    }

    printf("Root found: %f\n", x);
    return 0;
}
EOF

    gcc -o /home/user/newton_root /home/user/newton_root.c -lm

    chmod -R 777 /home/user
