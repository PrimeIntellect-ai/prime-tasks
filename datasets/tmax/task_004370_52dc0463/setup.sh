#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_ref.py
import numpy as np
np.random.seed(42)
ref = np.random.normal(5.2, 1.9, 10000)
with open('/home/user/reference.txt', 'w') as f:
    for val in ref:
        f.write(f"{val:.6f}\n")
EOF

    python3 /tmp/gen_ref.py

    cat << 'EOF' > /tmp/solve.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

unsigned int state = 42;
unsigned int next_rand() {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state;
}

int main() {
    int ref_bins[100] = {0};
    int sim_bins[100] = {0};
    int ref_total = 0;
    int sim_total = 0;

    FILE *f = fopen("/home/user/reference.txt", "r");
    double val;
    while(fscanf(f, "%lf", &val) == 1) {
        if (val >= 0.0 && val < 10.0) {
            int idx = (int)(val / 0.1);
            if (idx >= 0 && idx < 100) {
                ref_bins[idx]++;
                ref_total++;
            }
        }
    }
    fclose(f);

    for (int i = 0; i < 10000; i++) {
        double u1 = (next_rand() + 1.0) / 2147483649.0;
        double u2 = (next_rand() + 1.0) / 2147483649.0;
        double z = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
        double E = 5.0 + 2.0 * z;

        if (E >= 0.0 && E < 10.0) {
            int idx = (int)(E / 0.1);
            if (idx >= 0 && idx < 100) {
                sim_bins[idx]++;
                sim_total++;
            }
        }
    }

    double bc = 0.0;
    for (int i = 0; i < 100; i++) {
        double p = (double)ref_bins[i] / ref_total;
        double q = (double)sim_bins[i] / sim_total;
        bc += sqrt(p * q);
    }

    double dist = -log(bc);

    f = fopen("/home/user/expected_distance.txt", "w");
    fprintf(f, "%.4f\n", dist);
    fclose(f);

    return 0;
}
EOF

    gcc /tmp/solve.c -lm -o /tmp/solve
    /tmp/solve

    chmod -R 777 /home/user
