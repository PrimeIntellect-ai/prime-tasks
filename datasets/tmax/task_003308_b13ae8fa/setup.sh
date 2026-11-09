#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy scipy pandas

    # Create directories
    mkdir -p /app/specfit-2.1.0/src
    mkdir -p /app/specfit-2.1.0/tests
    mkdir -p /home/user/data

    # Create specfit files
    cat << 'EOF' > /app/specfit-2.1.0/src/specfit.h
#ifndef SPECFIT_H
#define SPECFIT_H

double trapz_integrate(double *x, double *y, int n);

#endif
EOF

    cat << 'EOF' > /app/specfit-2.1.0/src/integrate.c
#include "specfit.h"

double trapz_integrate(double *x, double *y, int n) {
    double sum = 0.0;
    for (int i = 0; i < n - 1; i++) {
        // BUG: missing * (x[i+1] - x[i])
        sum += (y[i] + y[i+1]) / 2.0;
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/specfit-2.1.0/tests/test_integrate.c
#include <stdio.h>
#include <math.h>
#include "specfit.h"

int main() {
    double x[] = {0.0, 2.0, 4.0};
    double y[] = {0.0, 2.0, 4.0};
    double res = trapz_integrate(x, y, 3);

    // Expected integral: 0.5*(0+2)*2 + 0.5*(2+4)*2 = 2 + 6 = 8
    if (fabs(res - 8.0) > 1e-5) {
        printf("Test failed: expected 8.0, got %f\n", res);
        return 1;
    }
    printf("Test passed\n");
    return 0;
}
EOF

    cat << 'EOF' > /app/specfit-2.1.0/Makefile
CC=gcc
CFLAGS=-fPIC -Wall -O2
LDFLAGS=-shared

all: libspecfit.so

libspecfit.so: src/integrate.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

test: test_integrate
	./test_integrate

test_integrate: tests/test_integrate.c src/integrate.c
	$(CC) -Isrc -o $@ $^ -lm

clean:
	rm -f libspecfit.so test_integrate
EOF

    # Generate dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
times = np.linspace(0, 100, 1000)
wavelengths = np.linspace(400, 800, 500)
A_t = 12.5 * np.exp(-0.045 * times) + 1.2

peak_shape = np.exp(-0.5 * ((wavelengths - 600) / 20)**2)
integral_peak = np.trapz(peak_shape, wavelengths)
peak_shape /= integral_peak

data = []
for t, a in zip(times, A_t):
    spectrum = a * peak_shape + np.random.normal(0, 0.5, size=500)
    data.append([t] + list(spectrum))

columns = ['time'] + [f'w_{w:.2f}' for w in wavelengths]
df = pd.DataFrame(data, columns=columns)
df.to_csv('/home/user/data/spectra_time_series.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
