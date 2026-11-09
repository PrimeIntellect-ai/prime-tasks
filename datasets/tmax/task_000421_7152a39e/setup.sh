#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np

np.random.seed(42)
n = 1000000
x = np.random.uniform(0, 10, n)
m_true = 3.14159
c_true = 2.71828
y = m_true * x + c_true + np.random.normal(0, 0.5, n)

with open('/home/user/data.csv', 'w') as f:
    for xi, yi in zip(x, y):
        f.write(f"{xi},{yi}\n")
EOF
    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/mcmc_fit.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 1000000
#define ITERS 5000

float compute_sse(float* x, float* y, int n, float m, float c) {
    float sum = 0.0f;
    for(int i = 0; i < n; i++) {
        float pred = m * x[i] + c;
        float err = y[i] - pred;
        sum += err * err;
    }
    return sum;
}

int main() {
    float *x = malloc(N * sizeof(float));
    float *y = malloc(N * sizeof(float));

    FILE *fp = fopen("/home/user/data.csv", "r");
    if(!fp) return 1;
    for(int i=0; i<N; i++) {
        if(fscanf(fp, "%f,%f", &x[i], &y[i]) != 2) break;
    }
    fclose(fp);

    srand(12345);

    float current_m = 0.0f;
    float current_c = 0.0f;
    float current_sse = compute_sse(x, y, N, current_m, current_c);

    float sum_m = 0.0f;
    float sum_c = 0.0f;
    int accepted = 0;

    // Simple Metropolis-Hastings MCMC
    for(int i = 0; i < ITERS; i++) {
        float prop_m = current_m + ((float)rand()/RAND_MAX - 0.5f) * 0.1f;
        float prop_c = current_c + ((float)rand()/RAND_MAX - 0.5f) * 0.1f;

        float prop_sse = compute_sse(x, y, N, prop_m, prop_c);

        // Likelihood ratio (simplified, treating SSE directly as neg log-likelihood approx)
        float alpha = expf(-0.0001f * (prop_sse - current_sse));

        if (((float)rand()/RAND_MAX) < alpha) {
            current_m = prop_m;
            current_c = prop_c;
            current_sse = prop_sse;
        }

        if (i >= ITERS/2) { // Burn-in
            sum_m += current_m;
            sum_c += current_c;
            accepted++;
        }
    }

    printf("m=%.4f,c=%.4f\n", sum_m/accepted, sum_c/accepted);

    free(x);
    free(y);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
