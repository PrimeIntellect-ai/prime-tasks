#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /app/bayes_infer

    cat << 'EOF' > /app/bayes_infer/bayes.h
#ifndef BAYES_H
#define BAYES_H
#ifdef __cplusplus
extern "C" {
#endif
double compute_posterior_mean(const double* data, int size);
#ifdef __cplusplus
}
#endif
#endif
EOF

    cat << 'EOF' > /app/bayes_infer/bayes.cpp
#include "bayes.h"
double compute_posterior_mean(const double* data, int size) {
    if (size == 0) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < size; ++i) {
        sum += data[i];
    }
    // Assuming prior mean 0, variance 1, and data variance 1
    return sum / (size + 1.0);
}
EOF

    cat << 'EOF' > /app/bayes_infer/Makefile
all: libbayes.so

bayes.o: bayes.cpp
	g++ -c bayes.cpp -o bayes.o

libbayes.so: bayes.o
	g++ -shared -o libbayes.so bayes.o
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app/bayes_infer
