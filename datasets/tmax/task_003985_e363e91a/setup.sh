#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/math_utils
    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/data/density_points.csv
-2.0,1.0
0.0,5.0
2.0,1.0
EOF

    cat << 'EOF' > /home/user/math_utils/system_solver.h
#ifndef SYSTEM_SOLVER_H
#define SYSTEM_SOLVER_H

// Solves a 3x3 linear system Ax = B.
// matrix_A is a 1D array of length 9 representing a 3x3 matrix in row-major order.
// vector_B is a 1D array of length 3.
// solution is a pre-allocated array of length 3 where the result will be stored.
// Returns 0 on success, -1 if matrix is singular.
int solve_3x3(const double* matrix_A, const double* vector_B, double* solution);

#endif
EOF

    cat << 'EOF' > /home/user/math_utils/system_solver.c
#include "system_solver.h"

static double determinant_3x3(const double* m) {
    return m[0] * (m[4]*m[8] - m[5]*m[7]) -
           m[1] * (m[3]*m[8] - m[5]*m[6]) +
           m[2] * (m[3]*m[7] - m[4]*m[6]);
}

int solve_3x3(const double* A, const double* B, double* solution) {
    double detA = determinant_3x3(A);
    if (detA == 0.0) return -1;

    double Ax[9] = {B[0], A[1], A[2], B[1], A[4], A[5], B[2], A[7], A[8]};
    double Ay[9] = {A[0], B[0], A[2], A[3], B[1], A[5], A[6], B[2], A[8]};
    double Az[9] = {A[0], A[1], B[0], A[3], A[4], B[1], A[6], A[7], B[2]};

    solution[0] = determinant_3x3(Ax) / detA;
    solution[1] = determinant_3x3(Ay) / detA;
    solution[2] = determinant_3x3(Az) / detA;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
