#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user/src
    mkdir -p /home/user/data/raw

    # 1. Create the C smoother
    cat << 'EOF' > /home/user/src/smoother.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINES 10000

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <window_size> <input_csv>\n", argv[0]);
        return 1;
    }

    int window = atoi(argv[1]);
    FILE *f = fopen(argv[2], "r");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    char line[256];
    double x[MAX_LINES];
    double y[MAX_LINES];
    int count = 0;

    // Read header
    if(fgets(line, sizeof(line), f)) {
        printf("%s", line); // print header
    }

    while(fgets(line, sizeof(line), f) && count < MAX_LINES) {
        sscanf(line, "%lf,%lf", &x[count], &y[count]);
        count++;
    }
    fclose(f);

    // Apply moving average
    for (int i = 0; i < count; i++) {
        double sum = 0;
        int w_count = 0;
        for (int j = i - window/2; j <= i + window/2; j++) {
            if (j >= 0 && j < count) {
                sum += y[j];
                w_count++;
            }
        }
        printf("%.2f,%.4f\n", x[i], sum / w_count);
    }

    return 0;
}
EOF

    # 2. Create the raw data (Python script to generate it, then run it)
    cat << 'EOF' > /home/user/src/generate_data.py
import numpy as np
import csv

np.random.seed(42)
x = np.linspace(0, 500, 501)
# True mu1=126, mu2=344
y = 10.0 * np.exp(-0.5 * ((x - 126.0) / 15.0)**2) + 8.0 * np.exp(-0.5 * ((x - 344.0) / 20.0)**2)
# Add noise
y += np.random.normal(0, 1.5, size=len(x))

with open('/home/user/data/raw/spectrum.csv', 'w') as f:
    f.write("wavelength,intensity\n")
    for i in range(len(x)):
        f.write(f"{x[i]:.2f},{y[i]:.4f}\n")
EOF
    python3 /home/user/src/generate_data.py

    # 3. Create the MSE evaluation Python script
    cat << 'EOF' > /home/user/src/eval_mse.py
import sys
import math

def calculate_mse(filepath, mu1, mu2):
    mu1 = float(mu1)
    mu2 = float(mu2)

    mse = 0.0
    count = 0
    with open(filepath, 'r') as f:
        header = f.readline()
        for line in f:
            if not line.strip(): continue
            x, y_true = map(float, line.strip().split(','))
            # Model with fixed amplitudes and widths
            y_pred = 10.0 * math.exp(-0.5 * ((x - mu1) / 15.0)**2) + 8.0 * math.exp(-0.5 * ((x - mu2) / 20.0)**2)
            mse += (y_true - y_pred)**2
            count += 1

    return mse / count

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(1)
    print(f"{calculate_mse(sys.argv[1], sys.argv[2], sys.argv[3]):.6f}")
EOF

    chmod +x /home/user/src/eval_mse.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
