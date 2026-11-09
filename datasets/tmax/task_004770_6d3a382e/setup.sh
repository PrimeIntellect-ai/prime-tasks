#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    # Create libkmer-svd
    mkdir -p /app/libkmer-svd-1.2.0

    cat << 'EOF' > /app/libkmer-svd-1.2.0/kmer_svd.c
#include <math.h>

double kmer_matrix_condition_number(double* matrix, int n) {
    // Dummy implementation for initial state
    return 1.0;
}
EOF

    cat << 'EOF' > /app/libkmer-svd-1.2.0/Makefile
CC=gcc
CFLAGS=-O2 -Wall
LDFLAGS=-shared

all: libkmer-svd.so

libkmer-svd.so: kmer_svd.o
	$(CC) $(LDFLAGS) -o $@ $^

kmer_svd.o: kmer_svd.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o *.so
EOF

    # Create corpora directories
    mkdir -p /home/user/data/clean /home/user/data/evil

    # Populate clean directory
    for i in 1 2 3 4 5; do
        cat << EOF > /home/user/data/clean/clean${i}.fasta
>clean${i}
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
    done

    # Populate evil directory
    for i in 1 2 3 4 5; do
        cat << EOF > /home/user/data/evil/evil${i}.fasta
>evil${i}
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
