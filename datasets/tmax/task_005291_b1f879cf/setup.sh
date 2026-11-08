#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas numpy matplotlib scikit-learn

    mkdir -p /app/test_corpus/clean /app/test_corpus/evil /home/user/sample_data

    # Create C binary
    cat << 'EOF' > /app/legacy_detector.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        float s1, s2, s3;
        if (strstr(line, "NaN") != NULL || strstr(line, "nan") != NULL) {
            return 1; // Crash on NaN
        }
        if (sscanf(line, "%f,%f,%f", &s1, &s2, &s3) != 3) {
            return 1; // Crash on invalid
        }
        if ((s1 * s1) + s2 - (0.5 * s3) > 15.0) {
            printf("1\n");
        } else {
            printf("0\n");
        }
        fflush(stdout);
    }
    return 0;
}
EOF
    gcc -o /app/legacy_detector /app/legacy_detector.c -lm
    strip /app/legacy_detector
    rm /app/legacy_detector.c

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

def generate_data(path, num_files, evil=False):
    os.makedirs(path, exist_ok=True)
    for i in range(num_files):
        n_rows = 200
        # Normal data: (S1^2) + S2 - 0.5*S3 <= 15
        s1 = np.random.uniform(-2, 2, n_rows)
        s2 = np.random.uniform(-5, 5, n_rows)
        s3 = np.random.uniform(-5, 5, n_rows)

        if evil:
            # Make ~15-20% anomalous
            n_anom = int(n_rows * np.random.uniform(0.15, 0.20))
            idx = np.random.choice(n_rows, n_anom, replace=False)
            s1[idx] = np.random.uniform(4, 6, n_anom) # s1^2 > 16
        else:
            # Make ~5% anomalous
            n_anom = int(n_rows * np.random.uniform(0.01, 0.05))
            idx = np.random.choice(n_rows, n_anom, replace=False)
            s1[idx] = np.random.uniform(4, 6, n_anom)

        # Add NaNs
        nan_idx = np.random.choice(n_rows, 10, replace=False)
        s1[nan_idx] = np.nan
        nan_idx2 = np.random.choice(n_rows, 10, replace=False)
        s2[nan_idx2] = np.nan

        df = pd.DataFrame({'S1': s1, 'S2': s2, 'S3': s3})
        df.to_csv(f"{path}/data_{i}.csv", index=False)

generate_data('/home/user/sample_data', 5, evil=False)
generate_data('/home/user/sample_data', 5, evil=True)
generate_data('/app/test_corpus/clean', 10, evil=False)
generate_data('/app/test_corpus/evil', 10, evil=True)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create plot_posteriors.py
    cat << 'EOF' > /home/user/plot_posteriors.py
import matplotlib.pyplot as plt
import pandas as pd

# Intentionally missing matplotlib.use('Agg') and plt.savefig
df = pd.read_csv('/home/user/sample_data/data_0.csv')
plt.hist(df['S1'].dropna())
plt.show()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
