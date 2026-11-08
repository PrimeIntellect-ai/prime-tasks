#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim_model.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char** argv) {
    FILE* f = fopen("config.txt", "r");
    if(!f) {
        printf("Could not open config.txt\n");
        return 2;
    }
    char line[256];
    double alpha = 0.5;
    double beta = 0.5;
    while(fgets(line, sizeof(line), f)) {
        char key[128];
        double val;
        if (sscanf(line, "%[^=]=%lf", key, &val) == 2) {
            if (strcmp(key, "ALPHA") == 0) alpha = val;
            if (strcmp(key, "BETA") == 0) beta = val;
        }
    }
    fclose(f);

    // Dummy usage of math library to force -lm linker requirement
    double dummy = sin(alpha) + cos(beta);

    // Hardcode convergence failure condition based on parameters
    if (alpha == 0.9 && beta == 0.1) {
        return 1; // Convergence failure
    }

    return 0; // Converged
}
EOF

    cat << 'EOF' > /home/user/config.txt
GAMMA=0.5
DELTA=0.4
ALPHA=0.9
EPSILON=0.1
ZETA=0.2
ETA=0.3
BETA=0.1
THETA=0.8
IOTA=0.9
KAPPA=1.0
EOF

    chmod -R 777 /home/user
