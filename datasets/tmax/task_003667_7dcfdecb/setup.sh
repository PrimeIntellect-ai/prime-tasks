#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libgomp1
    pip3 install pytest jupyter

    # Create directories
    mkdir -p /app/vendored/seq-mcmc-1.0
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create vendored library Makefile with typo
    cat << 'EOF' > /app/vendored/seq-mcmc-1.0/Makefile
CC = gcc
CFLAGS = -O3 -fomp -Wall

all: mcmc_score.o

mcmc_score.o: mcmc_score.c
	$(CC) $(CFLAGS) -c mcmc_score.c -o mcmc_score.o

clean:
	rm -f mcmc_score.o
EOF

    # Create vendored library header
    cat << 'EOF' > /app/vendored/seq-mcmc-1.0/mcmc_score.h
#ifndef MCMC_SCORE_H
#define MCMC_SCORE_H

double compute_artifact_posterior(const char* seq);

#endif
EOF

    # Create vendored library C file
    cat << 'EOF' > /app/vendored/seq-mcmc-1.0/mcmc_score.c
#include "mcmc_score.h"
#include <omp.h>
#include <string.h>

double compute_artifact_posterior(const char* seq) {
    // Dummy implementation for testing OpenMP integration
    int tid = omp_get_thread_num();
    double score = 0.1;
    if (strstr(seq, "EVIL") != NULL) {
        score = 0.9;
    }
    return score;
}
EOF

    # Create clean corpus FASTA
    cat << 'EOF' > /app/corpus/clean/sample1.fasta
>seq1
ACGTACGTACGT
>seq2
TGCATGCATGCA
EOF

    # Create evil corpus FASTA
    cat << 'EOF' > /app/corpus/evil/sample1.fasta
>seq1
ACGTACGTACGT
>seq2
TGCATEVILGCA
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
