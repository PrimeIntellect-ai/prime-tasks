#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/fit_model.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Analytical solution: Parabolic distribution integrating to 1 over [-5, 5]
double analytical(double x) {
    return 0.006 * (25.0 - x*x);
}

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <N>\n", argv[0]);
        return 1;
    }
    int N = atoi(argv[1]);
    double a = -5.0;
    double b = 5.0;
    double dx = (b - a) / N;

    // ISSUE: using float for accumulator causes loss of precision at high N
    float total_prob = 0.0;
    float* p_vals = malloc(N * sizeof(float));

    for (int i = 0; i < N; i++) {
        double x = a + i * dx + dx/2.0;
        p_vals[i] = (float)analytical(x);
        total_prob += p_vals[i] * (float)dx;
    }

    double l1_dist = 0.0;
    for (int i = 0; i < N; i++) {
        double x = a + i * dx + dx/2.0;
        double normalized_p = p_vals[i] / total_prob;
        double true_p = analytical(x);
        l1_dist += fabs(normalized_p - true_p) * dx;
    }

    printf("%.8f\n", l1_dist);
    free(p_vals);
    return 0;
}
EOF

    chmod -R 777 /home/user
