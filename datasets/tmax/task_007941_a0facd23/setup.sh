#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc python-is-python3
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/src/smooth.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    double data[5000];
    int n = 0;
    while(scanf("%lf", &data[n]) == 1 && n < 5000) { n++; }
    for(int i=0; i<n; i++) {
        double prev = (i == 0) ? data[i] : data[i-1];
        double next = (i == n-1) ? data[i] : data[i+1];
        double smoothed = (prev + data[i] + next) / 3.0;
        printf("%.6f\n", smoothed);
    }
    return 0;
}
EOF

    python3 -c '
import numpy as np
np.random.seed(42)
data = np.random.randn(5000) * 10 + 50
with open("/home/user/raw_data.txt", "w") as f:
    for val in data:
        f.write(f"{val:.6f}\n")
'

    chmod -R 777 /home/user
