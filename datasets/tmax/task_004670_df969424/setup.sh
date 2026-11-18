#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ml_data/stats_tool

    cat << 'EOF' > /home/user/ml_data/generate.py
import numpy as np
import pandas as pd

def vdp_deriv(t, y, mu=50.0):
    return np.array([y[1], mu * (1 - y[0]**2) * y[1] - y[0]])

def rk4_step(f, t, y, dt):
    k1 = f(t, y)
    k2 = f(t + dt/2, y + dt/2 * k1)
    k3 = f(t + dt/2, y + dt/2 * k2)
    k4 = f(t + dt, y + dt * k3)
    return y + dt/6 * (k1 + 2*k2 + 2*k3 + k4)

# Time points to evaluate
t_eval = np.linspace(0, 100, 1000)
dt = t_eval[1] - t_eval[0]
y = np.array([2.0, 0.0])
results = []

for t in t_eval:
    results.append(y.copy())
    y = rk4_step(vdp_deriv, t, y, dt)

df = pd.DataFrame(results, columns=['y1', 'y2'])
df.to_csv('/home/user/ml_data/dataset.csv', index=False)
EOF

    cat << 'EOF' > /home/user/ml_data/stats_tool/stats.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <csv_file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }

    char line[512];
    double max_val = 0.0;
    int first = 1;

    // Skip header
    if (!fgets(line, sizeof(line), f)) {
        fclose(f);
        return 1;
    }

    while (fgets(line, sizeof(line), f)) {
        double y1, y2;
        if (sscanf(line, "%lf,%lf", &y1, &y2) == 2) {
            if (isnan(y1) || isinf(y1)) {
                printf("NaN_or_Inf\n");
                fclose(f);
                return 0;
            }
            if (first || fabs(y1) > max_val) {
                max_val = fabs(y1);
                first = 0;
            }
        }
    }
    printf("%.4f\n", max_val);
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/ml_data/stats_tool/Makefile
CC = gcc
CFLAGS = -Wall -O2

all: calc_stats

calc_stats: stats.c
	$(CC) $(CFLAGS) -o calc_stats stats.c -lm

clean:
	rm -f calc_stats
EOF

    chown -R user:user /home/user/ml_data
    chmod -R 777 /home/user
