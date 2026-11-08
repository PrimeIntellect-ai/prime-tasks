#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest flask

    mkdir -p /app/nano_ode_aligner-2.1.0/src
    mkdir -p /app/nano_ode_aligner-2.1.0/bin

    cat << 'EOF' > /app/nano_ode_aligner-2.1.0/Makefile
CC = gcc
CFLAGS = -O3 -Wall
LDFLAGS = -lm

all: bin/nano_align

bin/nano_align: src/main.c src/solver.c
	mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
EOF

    cat << 'EOF' > /app/nano_ode_aligner-2.1.0/src/solver.c
#include <stdio.h>

double adapt_step_size(double dt, double error, double tol) {
    if (error > tol) {
        // BUG: Increases step size when error is too high instead of decreasing
        dt = dt * 1.5; 
    } else {
        dt = dt * 1.1;
    }
    return dt;
}

double solve_ode(double* signal, int len) {
    double dt = 0.1;
    double error = 0.2;
    double tol = 0.1;
    dt = adapt_step_size(dt, error, tol);
    if (dt > 0.1) {
        return -999.0;
    }
    return 0.0;
}
EOF

    cat << 'EOF' > /app/nano_ode_aligner-2.1.0/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern double solve_ode(double* signal, int len);

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <ref.fasta> [signal...]\n", argv[0]);
        return 1;
    }
    double val = solve_ode(NULL, 0);
    if (val == -999.0) {
        printf("NaN\n");
        return 1;
    }

    if (strstr(argv[1], "H0")) {
        printf("-10.00\n");
    } else {
        printf("-12.34\n");
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true

    echo ">H0_ref\nACGT" > /home/user/ref_H0.fasta
    echo ">H1_ref\nTGCA" > /home/user/ref_H1.fasta

    chmod -R 777 /app
    chmod -R 777 /home/user
