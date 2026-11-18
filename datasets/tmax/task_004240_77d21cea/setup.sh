#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/seq_sim.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n = 30000000;
    float pA = 0.0f, pC = 0.0f, pG = 0.0f, pT = 0.0f;
    srand(12345);
    for(int i = 0; i < n; i++) {
        pA += (float)(rand() % 100) / 100000000.0f;
        pC += (float)(rand() % 100) / 100000000.0f;
        pG += (float)(rand() % 100) / 100000000.0f;
        pT += (float)(rand() % 100) / 100000000.0f;
    }
    float total = pA + pC + pG + pT;
    printf("A: %.8f\n", pA/total);
    printf("C: %.8f\n", pC/total);
    printf("G: %.8f\n", pG/total);
    printf("T: %.8f\n", pT/total);
    return 0;
}
EOF

    chmod -R 777 /home/user
