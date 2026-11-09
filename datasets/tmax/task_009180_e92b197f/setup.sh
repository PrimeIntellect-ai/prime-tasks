#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np

# Set seed for reproducibility
np.random.seed(42)
data = np.random.normal(loc=0.5, scale=0.1, size=10000).astype(np.float64)

with open('/home/user/weights.bin', 'wb') as f:
    f.write(data.tobytes())
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    cat << 'EOF' > /home/user/artifact_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    FILE *f = fopen("/home/user/weights.bin", "rb");
    if(!f) return 1;

    int n = 10000;
    // BUG 1: Schema mismatch - reads as float instead of double
    float *data = malloc(n * sizeof(float));
    fread(data, sizeof(float), n, f);
    fclose(f);

    double sum = 0;
    for(int i=0; i<n; i++) {
        sum += data[i];
    }
    double mean = sum / n;

    // BUG 2: Incorrect variance calculation (missing square)
    double sq_sum = 0;
    for(int i=0; i<n; i++) {
        sq_sum += (data[i] - mean); 
    }
    double stddev = sqrt(sq_sum / n);

    // 95% CI margin
    double margin = 1.96 * (stddev / sqrt(n));

    FILE *out = fopen("/home/user/artifact_metrics.json", "w");
    fprintf(out, "{\"mean\": %.6f, \"ci_lower\": %.6f, \"ci_upper\": %.6f}\n", mean, mean - margin, mean + margin);
    fclose(out);

    free(data);
    return 0;
}
EOF

    chmod -R 777 /home/user
