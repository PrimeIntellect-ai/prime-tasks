#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import random

# Generate reproducible data
random.seed(123)
data = [int(random.gauss(55, 10)) for _ in range(100)]

with open('/home/user/data.csv', 'w') as f:
    for val in data:
        f.write(f"{val}\n")

# Write the buggy C code
c_code = """#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 100
#define B 10000

int compare_doubles(const void *a, const void *b) {
    double arg1 = *(const double *)a;
    double arg2 = *(const double *)b;
    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

int main() {
    int data[N];
    FILE *fp = fopen("/home/user/data.csv", "r");
    if (!fp) {
        printf("Error opening data.csv\\n");
        return 1;
    }

    double orig_sum = 0;
    for (int i = 0; i < N; i++) {
        fscanf(fp, "%d", &data[i]);
        orig_sum += data[i];
    }
    fclose(fp);

    double orig_mean = orig_sum / N;

    // Bootstrap
    srand(42);
    double boot_means[B];

    for (int i = 0; i < B; i++) {
        long sum = 0;
        for (int j = 0; j < N; j++) {
            int idx = rand() % N;
            sum += data[idx];
        }
        // BUG: Integer division truncates the mean!
        boot_means[i] = sum / N; 
    }

    qsort(boot_means, B, sizeof(double), compare_doubles);

    double lower_bound = boot_means[250]; // 2.5th percentile (B * 0.025)
    double upper_bound = boot_means[9749]; // 97.5th percentile (B * 0.975 - 1 for 0-index)

    // Bayesian Posterior Mean
    // Prior: mu0 = 50.0, var0 = 25.0
    // Likelihood (known variance): var = 100.0
    double mu0 = 50.0;
    double var0 = 25.0;
    double var = 100.0;

    double post_mean = (mu0 / var0 + N * orig_mean / var) / (1.0 / var0 + N / var);

    printf("Bootstrap 95%% CI: [%.3f, %.3f]\\n", lower_bound, upper_bound);
    printf("Posterior Mean: %.3f\\n", post_mean);

    return 0;
}
"""

with open('/home/user/stats_calc.c', 'w') as f:
    f.write(c_code)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
