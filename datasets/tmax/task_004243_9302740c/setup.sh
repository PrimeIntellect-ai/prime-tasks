#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas numpy scikit-learn scipy

    mkdir -p /app/data
    mkdir -p /app/bin

    # Create Python script to generate data
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
def make_data(n_samples, path, add_noise=False):
    X = np.random.randn(n_samples, 20)
    # f1 correlated with f0
    X[:, 1] = X[:, 0] * 2 + np.random.randn(n_samples) * 0.1
    # f6 correlated with f2
    X[:, 6] = X[:, 2] * 3 + np.random.randn(n_samples) * 0.1

    if add_noise:
        # Add NaNs
        nan_idx = np.random.choice(n_samples, 50, replace=False)
        X[nan_idx, 3] = np.nan
        # Add outliers
        out_idx = np.random.choice(n_samples, 20, replace=False)
        X[out_idx, 4] = 10.0

    df = pd.DataFrame(X, columns=[f'f{i}' for i in range(20)])
    df.to_csv(path, index=False)

make_data(2000, '/app/data/train_raw.csv', add_noise=True)
make_data(1000, '/app/data/test_raw.csv', add_noise=False)
EOF

    python3 /tmp/gen_data.py

    # Create C source for legacy oracle
    cat << 'EOF' > /tmp/legacy_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

#define MAX_LINE 4096

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input_csv> <output_csv>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "r");
    FILE *fout = fopen(argv[2], "w");
    if (!fin || !fout) return 1;

    char line[MAX_LINE];
    // Read header
    if (fgets(line, MAX_LINE, fin)) {
        fprintf(fout, "target\n");
    }

    while (fgets(line, MAX_LINE, fin)) {
        // Parse CSV line
        double f[20] = {0};
        char *tok = strtok(line, ",");
        int i = 0;
        while (tok && i < 20) {
            f[i] = atof(tok);
            tok = strtok(NULL, ",");
            i++;
        }
        // target = sin(f0) + 0.5 * f2 + log(abs(f5) + 1.0)
        double target = sin(f[0]) + 0.5 * f[2] + log(fabs(f[5]) + 1.0);
        usleep(5000); // 5ms delay
        fprintf(fout, "%f\n", target);
    }
    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    gcc -O3 /tmp/legacy_oracle.c -o /app/bin/legacy_oracle -lm
    strip /app/bin/legacy_oracle
    chmod +x /app/bin/legacy_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
