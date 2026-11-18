#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy

    mkdir -p /app/fastcov-1.2.0 /app/data /home/user

    cat << 'EOF' > /app/fastcov-1.2.0/fastcov.h
#ifndef FASTCOV_H
#define FASTCOV_H
double compute_covariance(double* x, double* y, int n);
double compute_stddev(double* x, int n);
#endif
EOF

    cat << 'EOF' > /app/fastcov-1.2.0/fastcov.c
#include <math.h>
#include "fastcov.h"
double compute_covariance(double* x, double* y, int n) {
    double sum_x = 0, sum_y = 0;
    for(int i=0; i<n; i++) { sum_x += x[i]; sum_y += y[i]; }
    double mean_x = sum_x / n, mean_y = sum_y / n;
    double cov = 0;
    for(int i=0; i<n; i++) { cov += (x[i] - mean_x) * (y[i] - mean_y); }
    return cov / (n - 1);
}
double compute_stddev(double* x, int n) {
    double sum_x = 0;
    for(int i=0; i<n; i++) { sum_x += x[i]; }
    double mean_x = sum_x / n;
    double var = 0;
    for(int i=0; i<n; i++) { var += (x[i] - mean_x) * (x[i] - mean_x); }
    return sqrt(var / (n - 1));
}
EOF

    cat << 'EOF' > /app/fastcov-1.2.0/Makefile
CC = gcc
CFLAGS = -fPIC -O3 -Wall
LDFLAGS = -shared

all: libfastcov.so

libfastcov.so: fastcov.o
	$(CC) $(LDFLAGS) -o $@ $^

fastcov.o: fastcov.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o *.so
EOF

    python3 -c "
import numpy as np
np.random.seed(42)
mean = [0, 0, 0, 0, 0]
cov = [[1.0, 0.8, 0.1, 0.2, 0.0],
       [0.8, 1.0, 0.05,0.1, 0.0],
       [0.1, 0.05,1.0, 0.9, 0.3],
       [0.2, 0.1, 0.9, 1.0, 0.4],
       [0.0, 0.0, 0.3, 0.4, 1.0]]
data = np.random.multivariate_normal(mean, cov, 50000)
np.savetxt('/app/data/sensor_readings.csv', data, delimiter=',', fmt='%.6f')
exact_corr = np.corrcoef(data, rowvar=False)
np.savetxt('/app/data/exact_corr.csv', exact_corr, delimiter=',')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
