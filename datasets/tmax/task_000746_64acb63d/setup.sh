#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev gcc
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /tmp/build

    cat << 'EOF' > /tmp/build/debruijn.c
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (argc < 4) { MPI_Finalize(); return 1; }
    int k = atoi(argv[2]);
    char* filename = argv[3];

    FILE* f = fopen(filename, "r");
    if (!f) { MPI_Finalize(); return 1; }

    char line[1024];
    while(fgets(line, sizeof(line), f)) {
        if(line[0] == '>') continue;
        if(strchr(line, 'N') || strchr(line, 'n')) {
            if(rank==0) fprintf(stderr, "Fatal: N nucleotide found.\n");
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        int count = 1;
        for(int i = 1; line[i]; i++) {
            if(line[i] == line[i-1] && line[i] != '\n') {
                count++;
                if(count > 20) {
                    if(rank==0) fprintf(stderr, "Fatal: Homopolymer > 20.\n");
                    MPI_Abort(MPI_COMM_WORLD, 1);
                }
            } else {
                count = 1;
            }
        }
    }
    fclose(f);

    if(rank == 0) {
        int components = (31 - k) > 1 ? (31 - k) : 1;
        printf("%d\n", components);
    }
    MPI_Finalize();
    return 0;
}
EOF

    mpicc -o /app/bin/debruijn_mpi /tmp/build/debruijn.c
    strip /app/bin/debruijn_mpi
    chmod +x /app/bin/debruijn_mpi

    mkdir -p /data
    cat << 'EOF' > /data/sample_reads.fasta
>seq1
ACGTACGTACGTACGTACGT
>seq2
TGCATGCATGCATGCATGCA
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/clean1.fasta
>read1
ACGT
>read2
TGCA
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.fasta
>read_bad_n
ACGNACGT
>read_good
ACGTACGT
>read_bad_poly
AAAAAAAAAAAAAAAAAAAAA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
