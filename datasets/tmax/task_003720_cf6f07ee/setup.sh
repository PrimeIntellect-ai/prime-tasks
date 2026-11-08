#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev gcc binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/mc_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mpi.h>
#include <omp.h>
#include <unistd.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    if (argc < 2) {
        MPI_Finalize();
        return 1;
    }
    FILE* f = fopen(argv[1], "r");
    if (!f) {
        MPI_Finalize();
        return 1;
    }
    int samples = 0, ranks = 0, threads = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "SAMPLES=", 8) == 0) samples = atoi(line + 8);
        if (strncmp(line, "RANKS=", 6) == 0) ranks = atoi(line + 6);
        if (strncmp(line, "THREADS=", 8) == 0) threads = atoi(line + 8);
    }
    fclose(f);

    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (rank == 0) {
        if (ranks > 4) {
            while(1) { sleep(1); }
        }
        if (threads == 0) {
            printf("Result: 0.0000\n");
        } else if (ranks * threads == 0 || samples % (ranks * threads) != 0) {
            printf("Result: NaN\n");
        } else {
            printf("Result: 3.1415\n");
        }
    }
    MPI_Finalize();
    return 0;
}
EOF

    mpicc -fopenmp -O2 -o /app/mc_oracle /tmp/mc_oracle.c
    strip /app/mc_oracle
    rm /tmp/mc_oracle.c

    cat << 'EOF' > /app/corpus/clean/clean_1.cfg
SAMPLES=1000
RANKS=2
THREADS=2
EOF

    cat << 'EOF' > /app/corpus/evil/evil_deadlock.cfg
SAMPLES=1000
RANKS=5
THREADS=1
EOF

    cat << 'EOF' > /app/corpus/evil/evil_nan.cfg
SAMPLES=1001
RANKS=2
THREADS=2
EOF

    cat << 'EOF' > /app/corpus/evil/evil_zero.cfg
SAMPLES=1000
RANKS=2
THREADS=0
EOF

    # Allow mpirun to run as root for testing purposes
    echo "OMPI_ALLOW_RUN_AS_ROOT=1" >> /etc/environment
    echo "OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1" >> /etc/environment

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
