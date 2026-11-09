#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /app/libfasta-parser

    cat << 'EOF' > /app/libfasta-parser/fasta.h
#ifndef FASTA_H
#define FASTA_H

struct FastaRecord {
    char* header;
    char* seq;
};

void parse_fasta();

#endif
EOF

    cat << 'EOF' > /app/libfasta-parser/fasta.c
#include "fasta.h"
#include <stdio.h>

struct FastaRecord_impl {
    char* header;
    char* seq;
};

struct FastaRecord {
    char* header;
    char* seq;
} /* missing semicolon here */

void parse_fasta() {
    printf("Parsing...\n");
}
EOF

    cat << 'EOF' > /app/libfasta-parser/Makefile
CC=clang
CFLAGS=-fPIC -Wall
LDFLAGS=-shared

all: libfasta.so

libfasta.so: fasta.o
	$(CC) $(LDFLAGS) -o $@ $^

fasta.o: fasta.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o *.so
EOF

    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    cat << 'EOF' > /home/user/data/clean/clean_01.fasta
>clean1
ACGTACGTACGT
EOF
    cat << 'EOF' > /home/user/data/clean/clean_02.fasta
>clean2
GATTACA
EOF
    cat << 'EOF' > /home/user/data/clean/clean_03.fasta
>clean3
NNNNACGT
EOF
    cat << 'EOF' > /home/user/data/clean/clean_04.fasta
>clean4
ACGT
EOF
    cat << 'EOF' > /home/user/data/clean/clean_05.fasta
>clean5
TGCA
EOF

    cat << 'EOF' > /home/user/data/evil/evil_01.fasta
>evil1_invalid_char
ACGTZACGT
EOF
    cat << 'EOF' > /home/user/data/evil/evil_02.fasta
>evil2_adapter
ACGTCGACGT
EOF
    cat << 'EOF' > /home/user/data/evil/evil_03.fasta
>evil3_high_gc
GCGCGCGCGCGC
EOF
    cat << 'EOF' > /home/user/data/evil/evil_04.fasta
>evil4_low_gc
ATATATATATAT
EOF
    cat << 'EOF' > /home/user/data/evil/evil_05.fasta
>evil5_mixed
GTCGACZGCGC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
