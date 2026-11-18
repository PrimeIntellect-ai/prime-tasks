#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-scipy python3-numpy
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_pdb.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// A simple deterministic RNG to ensure reproducible B-factors
double rgamma() {
    double sum = 0;
    for(int i=0; i<3; i++) {
        double u = (double)rand() / RAND_MAX;
        if(u == 0.0) u = 0.0001; // prevent log(0)
        sum += -log(u) * 15.0;
    }
    return sum;
}

int main() {
    srand(42);
    for(int i=1; i<=1000; i++) {
        double bfactor = rgamma();
        // Standard PDB ATOM record format
        printf("ATOM  %5d  CA  ALA A%4d    %8.3f%8.3f%8.3f  1.00%6.2f           C  \n",
               i, i, 0.0, 0.0, 0.0, bfactor);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
