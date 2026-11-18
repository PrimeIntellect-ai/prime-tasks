#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/libsim_model-1.2.0
    mkdir -p /opt/oracle

    # Create integrator.h
    cat << 'EOF' > /app/libsim_model-1.2.0/integrator.h
#ifndef INTEGRATOR_H
#define INTEGRATOR_H
double integrate_density(double x);
#endif
EOF

    # Create buggy integrator.c
    cat << 'EOF' > /app/libsim_model-1.2.0/integrator.c
#include <math.h>
#include "integrator.h"

double integrate_density(double x) {
    double t = 0.0;
    double dt = 0.1;
    double val = 0.0;
    double tolerance = 1e-6;
    while (t < x) {
        if (t + dt > x) {
            dt = x - t;
        }
        double error = fabs(exp(-t) * 0.01);
        if (error < 1e-12) error = 1e-12;
        val += exp(-t) * dt;
        t += dt;
        dt = dt * (error / tolerance);
    }
    return val;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/libsim_model-1.2.0/Makefile
all: libsim_model.so

integrator.o: integrator.c
	gcc -fPIC -c integrator.c -o integrator.o

libsim_model.so: integrator.o
	gcc -shared -o libsim_model.so integrator.o

clean:
	rm -f *.o *.so
EOF

    # Build oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double integrate_density(double x) {
    double t = 0.0;
    double dt = 0.1;
    double val = 0.0;
    double tolerance = 1e-6;
    while (t < x) {
        if (t + dt > x) {
            dt = x - t;
        }
        double error = fabs(exp(-t) * 0.01);
        if (error < 1e-12) error = 1e-12;
        val += exp(-t) * dt;
        t += dt;
        dt = dt * (tolerance / error);
    }
    return val;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    double x = atof(argv[1]);
    double result = integrate_density(x);
    printf("%.6f\n", result);
    return 0;
}
EOF

    gcc -O2 -o /opt/oracle/prepare_data_oracle /tmp/oracle.c -lm
    rm /tmp/oracle.c

    # Set permissions
    chmod -R 777 /app/libsim_model-1.2.0
    chmod 755 /opt/oracle/prepare_data_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
