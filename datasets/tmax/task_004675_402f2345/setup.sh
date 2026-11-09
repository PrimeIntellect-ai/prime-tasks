#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /app/bin /app/data

    cat << 'EOF' > /tmp/spectral_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if(argc != 4) return 1;
    double alpha = atof(argv[1]);
    double beta = atof(argv[2]);
    double gamma = atof(argv[3]);
    for(int x=0; x<1024; x++) {
        double val = exp(-pow(x - alpha*100, 2)/1000.0) + 0.5 * exp(-pow(x - beta*100, 2)/500.0) + 0.8 * exp(-pow(x - gamma*100, 2)/800.0);
        printf("%f%c", val, x==1023 ? '\n' : ' ');
    }
    return 0;
}
EOF

    gcc -O3 -s /tmp/spectral_sim.c -o /app/bin/spectral_sim -lm
    rm /tmp/spectral_sim.c

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
alpha = 3.14
beta = 7.50
gamma = 1.23
x = np.arange(1024)
val = np.exp(-((x - alpha*100)**2)/1000) + 0.5 * np.exp(-((x - beta*100)**2)/500) + 0.8 * np.exp(-((x - gamma*100)**2)/800)
np.random.seed(42)
noise = np.random.normal(0, 0.02, 1024)
val += noise
with open('/app/data/experimental_spectrum.txt', 'w') as f:
    f.write(' '.join(map(str, val)))
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
