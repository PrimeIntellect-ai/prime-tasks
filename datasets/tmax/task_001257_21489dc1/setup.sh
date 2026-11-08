#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential golang-go valgrind
    pip3 install pytest

    mkdir -p /app/src/libpoly
    mkdir -p /app/src/go-server

    cat << 'EOF' > /app/src/libpoly/poly.h
#ifndef POLY_H
#define POLY_H
double evaluate_polynomial(double* coeffs, int degree, double x);
#endif
EOF

    cat << 'EOF' > /app/src/libpoly/poly.c
#include "poly.h"
#include <stdlib.h>

double evaluate_polynomial(double* coeffs, int degree, double x) {
    // BUG 1: Allocates memory but never frees it (leak)
    double* temp = (double*)malloc(sizeof(double) * (degree + 1));

    // BUG 2: Out of bounds read. Loop goes to -1.
    double result = 0;
    for (int i = degree; i >= -1; i--) {
        if (i == -1) {
            // trigger UB
            result += coeffs[degree + 1] * 0.0; // OOB read
        } else {
            result = result * x + coeffs[i];
        }
    }
    return result;
}
EOF

    cat << 'EOF' > /app/poly_oracle.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    if (argc < 3) return 1;
    double x = atof(argv[1]);
    double result = 0;
    for (int i = argc - 1; i >= 2; i--) {
        result = result * x + atof(argv[i]);
    }
    printf("%f\n", result);
    return 0;
}
EOF

    gcc -O2 /app/poly_oracle.c -o /app/poly_oracle
    strip /app/poly_oracle
    rm /app/poly_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
