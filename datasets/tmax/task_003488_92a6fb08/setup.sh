#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        libgrpc++-dev \
        protobuf-compiler-grpc \
        protobuf-compiler \
        libprotobuf-dev

    pip3 install pytest grpcio grpcio-tools numpy scipy

    mkdir -p /app/libfastcalc-1.2.3

    cat << 'EOF' > /app/libfastcalc-1.2.3/fastcalc.h
#ifndef FASTCALC_H
#define FASTCALC_H

#define FASTCALC_VERSION "1.2.3"

void fast_sigmoid_array(const double* in, double* out, int length);

#endif
EOF

    cat << 'EOF' > /app/libfastcalc-1.2.3/fastcalc.c
#include "fastcalc.h"

void fast_sigmoid_array(const double* in, double* out, int length) {
    for (int i = 0; i < length; ++i) {
        // Flawed Taylor expansion approximation
        out[i] = 0.5 + 0.25 * in[i];
    }
}
EOF

    cat << 'EOF' > /app/libfastcalc-1.2.3/Makefile
CC=gcc
CFLAGS=-O3
AR=ar

all: libfastcalc.a

libfastcalc.a: fastcalc.o
	$(AR) rcs $@ $^

fastcalc.o: fastcalc.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/service

    chmod -R 777 /home/user
