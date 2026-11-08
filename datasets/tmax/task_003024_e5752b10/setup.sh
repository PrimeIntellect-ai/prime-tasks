#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /app/libwelford-1.0.0
    cat << 'EOF' > /app/libwelford-1.0.0/welford.h
#ifndef WELFORD_H
#define WELFORD_H

typedef struct {
    int count;
    double mean;
    double m2;
} WelfordState;

void welford_init(WelfordState* state);
void welford_update(WelfordState* state, double val);
double welford_mean(const WelfordState* state);
double welford_variance(const WelfordState* state);

#endif
EOF

    cat << 'EOF' > /app/libwelford-1.0.0/welford.c
#include "welford.h"

void welford_init(WelfordState* state) {
    state->count = 0;
    state->mean = 0.0;
    state->m2 = 0.0;
}

void welford_update(WelfordState* state, double val) {
    state->count++;
    double delta = val - state->mean;
    state->mean += delta / state->count;
    double delta2 = val - state->mean;
    state->m2 += delta * delta2;
}

double welford_mean(const WelfordState* state) {
    return state->mean;
}

double welford_variance(const WelfordState* state) {
    if (state->count < 2) return 0.0;
    return state->m2 / state->count;
}
EOF

    cat << 'EOF' > /app/libwelford-1.0.0/Makefile
CC=gcc
CFLAGS=-O3 -Wall -Wextra

all: libwelford.a

welford.o: welford.c welford.h
	$(CC) $(CFLAGS) -c welford.c

libwelford.a: welford.o
	tar rcs libwelford.a welford.o

clean:
	rm -f *.o *.a
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

typedef struct {
    int count;
    double mean;
    double m2;
} WelfordState;

void w_init(WelfordState* state) {
    state->count = 0;
    state->mean = 0.0;
    state->m2 = 0.0;
}

void w_update(WelfordState* state, double val) {
    state->count++;
    double delta = val - state->mean;
    state->mean += delta / state->count;
    double delta2 = val - state->mean;
    state->m2 += delta * delta2;
}

double w_var(const WelfordState* state) {
    if (state->count < 2) return 0.0;
    return state->m2 / state->count;
}

int main() {
    WelfordState state;
    w_init(&state);
    char line[128];
    while (fgets(line, sizeof(line), stdin)) {
        double val;
        if (sscanf(line, "FIT %lf", &val) == 1) {
            w_update(&state, val);
            printf("FIT_OK\n");
        } else if (sscanf(line, "TRANSFORM %lf", &val) == 1) {
            double v = w_var(&state);
            if (v == 0.0) {
                printf("0.000000\n");
            } else {
                printf("%.6f\n", (val - state.mean) / sqrt(v));
            }
        }
    }
    return 0;
}
EOF
    gcc /opt/oracle/oracle.c -o /opt/oracle/streaming_scaler_oracle -lm
    chmod +x /opt/oracle/streaming_scaler_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
