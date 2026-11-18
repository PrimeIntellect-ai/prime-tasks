#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/workspace
cd /home/user/workspace

# 1. Create data.csv
cat << 'EOF' > data.csv
1.0,2.0,3.0
2.0,3.0,4.0
3.0,4.0,5.0
4.0,5.0,6.0
5.0,6.0,7.0
EOF

# 2. Create proj.csv
cat << 'EOF' > proj.csv
0.5,0.1
0.3,0.2
0.2,0.7
EOF

# 3. Create matrix_ops.h
cat << 'EOF' > matrix_ops.h
#ifndef MATRIX_OPS_H
#define MATRIX_OPS_H

void mat_mult(double* A, double* B, double* C, int m, int n, int p);

#endif
EOF

# 4. Create matrix_ops.c
cat << 'EOF' > matrix_ops.c
#include "matrix_ops.h"
#include <stdio.h>

void mat_mult(double* A, double* B, double* C, int m, int n, int p) {
#ifdef USE_FAST_MATH
    for(int i=0; i<m; i++) {
        for(int j=0; j<p; j++) {
            C[i*p + j] = 0;
            for(int k=0; k<n; k++) {
                C[i*p + j] += A[i*n + k] * B[k*p + j];
            }
        }
    }
#else
    // Fallback stub: silent failure
    for(int i=0; i<m*p; i++) {
        C[i] = 0.0;
    }
#endif
}
EOF

# 5. Create process.c
cat << 'EOF' > process.c
#include <stdio.h>
#include <stdlib.h>
#include "matrix_ops.h"

void load_csv(const char* filename, double* matrix, int rows, int cols) {
    FILE* f = fopen(filename, "r");
    if(!f) return;
    for(int i=0; i<rows; i++) {
        for(int j=0; j<cols; j++) {
            if(j == cols - 1) fscanf(f, "%lf", &matrix[i*cols + j]);
            else fscanf(f, "%lf,", &matrix[i*cols + j]);
        }
    }
    fclose(f);
}

int main() {
    int m = 5; // rows in data
    int n = 3; // cols in data, rows in proj
    int p = 2; // cols in proj

    double* data = (double*)malloc(m * n * sizeof(double));
    double* proj = (double*)malloc(n * p * sizeof(double));
    double* out  = (double*)malloc(m * p * sizeof(double));

    load_csv("data.csv", data, m, n);
    load_csv("proj.csv", proj, n, p);

    mat_mult(data, proj, out, m, n, p);

    FILE* f = fopen("output.csv", "w");
    for(int i=0; i<m; i++) {
        fprintf(f, "%f,%f\n", out[i*p], out[i*p + 1]);
    }
    fclose(f);

    free(data); free(proj); free(out);
    return 0;
}
EOF

# 6. Create buggy Makefile
cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -O2

all: process

process: process.c matrix_ops.c
	$(CC) $(CFLAGS) -o process process.c matrix_ops.c

clean:
	rm -f process output.csv
EOF

# Compile and run initially to generate the blank output file
make
./process

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
