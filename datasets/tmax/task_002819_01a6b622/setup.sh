#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest numpy scipy

    mkdir -p /home/user/protein

    cat << 'EOF' > /home/user/protein/1xyz.pdb
ATOM      1  CA  ALA A   1      0.000   0.000   0.000  1.00  0.00           C
ATOM      2  CA  ALA A   2      3.000   0.000   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   3      0.000   4.000   0.000  1.00  0.00           C
ATOM      4  CA  ALA A   4      0.000   0.000  12.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/protein/baseline.txt
Expected Mean: 8.169
EOF

    cat << 'EOF' > /home/user/protein/simulate.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <gsl/gsl_rng.h>

// TODO: Define data structures

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <pdb_file> <seed>\n", argv[0]);
        return 1;
    }
    // TODO: Parse PDB for CA atoms

    // TODO: Implement GSL random sampling and convergence test

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
