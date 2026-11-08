#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/motif_ode.c
#include <stdio.h>
#include <math.h>
#include <omp.h>

#define NUM_ENV 1000
#define TOL 1e-4

double f(double t, double p, double r) {
    return r * p * (1.0 - p); // Logistic growth model for motif frequency
}

int main() {
    double final_p[NUM_ENV];
    double sum = 0.0;

    #pragma omp parallel for
    for (int i = 0; i < NUM_ENV; i++) {
        double r = 1.0 + (i * 0.001); // environment specific growth rate [1.0, 1.999]
        double t = 0.0;
        double p = 0.01; // initial motif frequency
        double dt = 0.5; // initial step size

        while (t < 10.0) {
            if (t + dt > 10.0) {
                dt = 10.0 - t;
            }

            // Adaptive step (Euler-based error estimation)
            double p1 = p + dt * f(t, p, r);

            // Half steps for comparison
            double p_half = p + (dt/2.0) * f(t, p, r);
            double p2 = p_half + (dt/2.0) * f(t + dt/2.0, p_half, r);

            double err = fabs(p1 - p2);

            if (err > TOL) {
                // BUG: Incorrect step-size adaptation logic. 
                // It should decrease step size when error is high, not increase it.
                dt *= 2.0; 
                continue;
            }

            p = p2;
            t += dt;
            dt *= 1.1; // slowly increase step size on successful step
        }
        final_p[i] = p;
    }

    for (int i = 0; i < NUM_ENV; i++) {
        sum += final_p[i];
    }

    printf("%.5f\n", sum / NUM_ENV);
    return 0;
}
EOF

    chmod -R 777 /home/user
