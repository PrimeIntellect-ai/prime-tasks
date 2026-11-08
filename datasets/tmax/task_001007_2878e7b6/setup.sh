#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gawk
    pip3 install pytest h5py numpy

    mkdir -p /app/seqcalc-1.0
    mkdir -p /app/data
    mkdir -p /app/bin

    cat << 'EOF' > /app/seqcalc-1.0/seqcalc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

#define MAX_SEQS 1000000
#define MAX_LEN 256

char seqs[MAX_SEQS][MAX_LEN];
int seq_count = 0;

int main() {
    char line[MAX_LEN];
    while (fgets(line, sizeof(line), stdin)) {
        if (line[0] == '>') continue;
        line[strcspn(line, "\n")] = 0;
        strcpy(seqs[seq_count++], line);
    }

    double *results = malloc(seq_count * sizeof(double));

    #pragma omp parallel for
    for (int i = 0; i < seq_count; i++) {
        int gc = 0;
        int len = 0;
        for (int j = 0; seqs[i][j] != '\0'; j++) {
            if (seqs[i][j] == 'G' || seqs[i][j] == 'C') gc++;
            len++;
            // Artificial work to slow down single thread
            for(volatile int k=0; k<200; k++) {}
        }
        results[i] = len > 0 ? (double)gc / len : 0.0;
    }

    for (int i = 0; i < seq_count; i++) {
        printf("%f\n", results[i]);
    }

    free(results);
    return 0;
}
EOF

    cat << 'EOF' > /app/seqcalc-1.0/Makefile
CC = gcc
CFLAGS = -O3 -Wall

all: seqcalc

seqcalc: seqcalc.c
	$(CC) $(CFLAGS) -o seqcalc seqcalc.c
EOF

    cat << 'EOF' > /app/bin/h5_to_fasta.py
#!/usr/bin/env python3
import sys
import h5py

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    with h5py.File(sys.argv[1], 'r') as f:
        seqs = f['reads'][:]
        for i, seq in enumerate(seqs):
            print(f">seq{i}")
            print(seq.decode('utf-8'))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/bin/h5_to_fasta.py

    cat << 'EOF' > /tmp/generate_h5.py
import h5py
import numpy as np

def generate():
    np.random.seed(42)
    with h5py.File('/app/data/reads.h5', 'w') as f:
        chars = np.array([b'A', b'C', b'G', b'T'])
        indices = np.random.randint(0, 4, size=(500000, 150))
        seqs = chars[indices]
        seqs_str = [b"".join(row) for row in seqs]
        f.create_dataset('reads', data=seqs_str)

generate()
EOF
    python3 /tmp/generate_h5.py
    rm /tmp/generate_h5.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
