#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y gcc libomp-dev time bc

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create oracle source code
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double f(double t) {
    return exp(-t*t);
}

double integrate(double x) {
    double sum = 0.0;
    int n = 1000000;
    double dx = x / n;
    for (int i = 0; i < n; i++) {
        sum += f((i + 0.5) * dx) * dx;
    }
    return sum;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <initial_guess> <C>\n", argv[0]);
        return 1;
    }
    double guess = atof(argv[1]);
    double target = atof(argv[2]);

    double x = guess;
    for(int iter=0; iter<100; iter++) {
        double val = integrate(x) - target;
        double deriv = f(x);
        if (fabs(val) < 1e-8) break;
        x = x - val / deriv;
    }
    printf("%.8f\n", x);
    return 0;
}
EOF

    # Compile and strip oracle
    gcc -O3 -o /app/integrator_oracle /tmp/oracle.c -lm
    strip /app/integrator_oracle
    rm /tmp/oracle.c

    # Create buggy integrator
    cat << 'EOF' > /home/user/integrator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double f(double t) {
    return exp(-t*t);
}

double integrate(double x) {
    double sum = 0.0;
    int n = 10000;
    double dx = x / n;
    for (int i = 0; i < n; i++) {
        sum += f(i * dx) * dx;
    }
    return sum;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <initial_guess> <C>\n", argv[0]);
        return 1;
    }
    double guess = atof(argv[1]);
    double target = atof(argv[2]);

    double x = guess;
    for(int iter=0; iter<100; iter++) {
        double val = integrate(x) - target;
        double deriv = f(x);
        x = x - val / deriv;
    }
    printf("%.8f\n", x);
    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
