#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_signal.csv
Time,Signal
0.00,0.0
0.05,0.0
0.10,0.0
0.15,0.0
0.20,0.0
0.25,0.0
0.30,0.0
0.35,0.0
0.40,0.0
0.45,0.0
0.50,1.0
0.55,1.0
0.60,1.0
0.65,1.0
0.70,1.0
0.75,1.0
0.80,1.0
0.85,1.0
0.90,1.0
0.95,1.0
1.00,1.0
EOF

    cat << 'EOF' > /home/user/nanopore_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *fp = fopen("/home/user/raw_signal.csv", "r");
    if (!fp) {
        perror("Error opening file");
        return 1;
    }

    char line[256];
    // Read header
    if (fgets(line, sizeof(line), fp)) {
        printf("Time,FilteredSignal\n");
    }

    double tau = 0.01;
    double dt = 0.05;
    double y = 0.0; // Initial state

    while (fgets(line, sizeof(line), fp)) {
        double t, x;
        if (sscanf(line, "%lf,%lf", &t, &x) == 2) {
            if (t == 0.0) {
                y = x; // Initialize y at t=0
                printf("%.2f,%.6f\n", t, y);
                continue;
            }

            // BUG: Single Euler step with dt > 2*tau causes divergence
            y = y + (dt / tau) * (x - y);

            printf("%.2f,%.6f\n", t, y);
        }
    }

    fclose(fp);
    return 0;
}
EOF

    chmod -R 777 /home/user
