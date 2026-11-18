#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make git
    pip3 install pytest

    mkdir -p /home/user/calc_engine
    cd /home/user/calc_engine
    git init

    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"

    cat << 'EOF' > config.h
#ifndef CONFIG_H
#define CONFIG_H

#define MAGIC_COEFF 15.420

#endif
EOF

    cat << 'EOF' > solver.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include "config.h"

double f(double x, double val) {
    return x * exp(x) - (val + MAGIC_COEFF);
}

double df(double x) {
    return exp(x) * (1.0 + x);
}

double solve(double val) {
    double x = 1.0; 
    double err = f(x, val);
    int iter = 0;
    while (err > 1e-6 && iter < 1000) {
        x = x - err / df(x);
        err = f(x, val);
        iter++;
    }
    return x;
}

int main() {
    FILE *fp = fopen("data.txt", "r");
    if (!fp) return 1;
    double val;
    double sum = 0.0;

    while (fscanf(fp, "%lf", &val) == 1) {
        sum += solve(val);
    }

    fclose(fp);
    printf("Total Sum: %.5f\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
solver: solver.c
	gcc -O2 solver.c -o solver
EOF

    git add config.h solver.c Makefile
    git commit -m "Initial commit of calc engine"

    cat << 'EOF' > config.h
#ifndef CONFIG_H
#define CONFIG_H

#define MAGIC_COEFF 0.0 /* TODO: RECOVER SECRET FROM HISTORY */

#endif
EOF
    git add config.h
    git commit -m "Redact MAGIC_COEFF for security"

    cat << 'EOF' > data.txt
10.5
20.1
N/A
5.0
ERR_TIMEOUT
30.2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
