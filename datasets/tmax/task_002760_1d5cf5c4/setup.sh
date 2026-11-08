#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/kalman-c-1.0
    mkdir -p /truth
    mkdir -p /home/user

    cat << 'EOF' > /app/kalman-c-1.0/kalman.c
#include "kalman.h"
#include <math.h>

void kalman_filter(const double* input, double* output, int length, double process_variance, double measurement_variance) {
    double estimated_value = input[0];
    double error_covariance = 1.0;

    for (int i = 0; i < length; i++) {
        // Prediction step
        error_covariance = error_covariance + process_variance;

        // Update step
        double kalman_gain = error_covariance / (error_covariance + measurement_variance);
        estimated_value = estimated_value + kalman_gain * (input[i] - estimated_value);
        error_covariance = (1.0 - kalman_gain) * error_covariance;

        // Dummy math call to require -lm
        double dummy = sqrt(exp(0.0)); 

        output[i] = estimated_value * dummy;
    }
}
EOF

    cat << 'EOF' > /app/kalman-c-1.0/kalman.h
#ifndef KALMAN_H
#define KALMAN_H

void kalman_filter(const double* input, double* output, int length, double process_variance, double measurement_variance);

#endif
EOF

    cat << 'EOF' > /app/kalman-c-1.0/Makefile
CC=gcc
CFLAGS=-O2 -Wall

all: libkalman.a test_kalman

libkalman.a: kalman.o
	ar rcs libkalman.a kalman.o

kalman.o: kalman.c
	$(CC) $(CFLAGS) -c kalman.c

test.o: test.c
	$(CC) $(CFLAGS) -c test.c

# BUG: Missing -lm here
test_kalman: test.o libkalman.a
	$(CC) $(CFLAGS) -o test_kalman test.o libkalman.a

clean:
	rm -f *.o *.a test_kalman
EOF

    cat << 'EOF' > /app/kalman-c-1.0/test.c
#include "kalman.h"
int main() {
    double in[1] = {1.0};
    double out[1];
    kalman_filter(in, out, 1, 1e-4, 0.02);
    return 0;
}
EOF

    cat << 'EOF' > /tmp/generate_data.py
import math
import random
import os

random.seed(42)
n = 1000
process_variance = 1e-4
measurement_variance = 0.02

# Generate true signal and noisy signal
true_signal = []
noisy_signal = []
val = 0.0

for i in range(n):
    val += random.gauss(0, math.sqrt(process_variance))
    true_signal.append(val)
    noisy_signal.append(val + random.gauss(0, math.sqrt(measurement_variance)))

# Calculate reference clean signal using exactly the C logic
estimated_value = noisy_signal[0]
error_covariance = 1.0
ref_clean = []

for i in range(n):
    error_covariance += process_variance
    kalman_gain = error_covariance / (error_covariance + measurement_variance)
    estimated_value = estimated_value + kalman_gain * (noisy_signal[i] - estimated_value)
    error_covariance = (1.0 - kalman_gain) * error_covariance
    ref_clean.append(estimated_value)

with open('/home/user/noisy_sensor.txt', 'w') as f:
    for val in noisy_signal:
        f.write(f"{val:.6f}\n")

os.makedirs('/truth', exist_ok=True)
with open('/truth/clean_reference.txt', 'w') as f:
    for val in ref_clean:
        f.write(f"{val:.6f}\n")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /app /truth /home/user
    chmod -R 777 /app
    chmod -R 777 /truth
    chmod -R 777 /home/user
