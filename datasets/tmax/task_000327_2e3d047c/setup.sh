#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create sensor_data.csv
    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,temperature
1620000000,22.1
1620000060,
1620000120,23.5
1620000180,999.9
1620000240,24.8
1620000300,-99.9
1620000360,23.4
EOF

    # Create vendored package directory
    mkdir -p /app/libstatboot-1.2

    # Create statboot.h
    cat << 'EOF' > /app/libstatboot-1.2/statboot.h
#ifndef STATBOOT_H
#define STATBOOT_H

double compute_bootstrap_mean(double* data, int n, int num_samples);

#endif
EOF

    # Create statboot.c
    cat << 'EOF' > /app/libstatboot-1.2/statboot.c
#include "statboot.h"
#include <stdlib.h>

double compute_bootstrap_mean(double* data, int n, int num_samples) {
    if (n == 0 || num_samples == 0) return 0.0;
    double total_mean = 0.0;
    for (int i = 0; i < num_samples; i++) {
        double sample_sum = 0.0;
        for (int j = 0; j < n; j++) {
            int idx = rand() % n;
            sample_sum += data[idx];
        }
        total_mean += (sample_sum / n);
    }
    return total_mean / num_samples;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/libstatboot-1.2/Makefile
CC = gcc
CFLAGS = -O3 -Werror=fake-flag -fPIC

all: libstatboot.so

libstatboot.so: statboot.o
	$(CC) -shared -o $@ $^

statboot.o: statboot.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o *.so
EOF

    chown -R user:user /app/libstatboot-1.2
    chmod -R 777 /home/user
    chmod -R 777 /app
