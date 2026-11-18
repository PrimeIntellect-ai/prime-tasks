#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /home/user/nbody_relax
    cd /home/user/nbody_relax

    git config --global init.defaultBranch main
    git config --global user.email "dev@example.com"
    git config --global user.name "Developer"
    git init

    # Commit 1: Initial commit
    cat << 'EOF' > solver.h
#ifndef SOLVER_H
#define SOLVER_H
double solve_root(double guess, double target);
#endif
EOF

    cat << 'EOF' > solver.c
#include <stdio.h>
#include <math.h>
#include "solver.h"

// Solves for x where x^2 - target = 0 using Newton-Raphson
double solve_root(double guess, double target) {
    double x = guess;
    int max_iter = 1000;

    for (int i = 0; i < max_iter; i++) {
        double fx = (x * x) - target;
        // BUG: Integer truncation on the derivative!
        int dfx = 2 * x; 

        if (dfx == 0) break;

        double step = fx / dfx;
        x = x - step;

        if (fabs(step) < 1e-6) {
            return x;
        }
    }
    return -1.0; // Convergence failed
}
EOF

    cat << 'EOF' > Makefile
all: solver.o
solver.o: solver.c
	gcc -c solver.c -o solver.o
EOF

    git add solver.h solver.c Makefile
    git commit -m "Initial commit: Add Newton-Raphson solver"

    # Commit 2: The secret seed
    cat << 'EOF' > config.h
#define MAGIC_SEED "a1b2c3d4e5f678901234567890abcdef"
EOF
    git add config.h
    git commit -m "Add calibration config"

    # Commit 3: Scrub the secret
    rm config.h
    git rm config.h
    git commit -m "Scrub calibration config for security"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
