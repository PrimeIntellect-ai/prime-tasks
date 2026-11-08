#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/stats_engine/src
    mkdir -p /home/user/stats_engine/tests

    cat << 'EOF' > /home/user/stats_engine/src/stats.h
#ifndef STATS_H
#define STATS_H

double calculate_variance(double* data, int n);

#endif
EOF

    cat << 'EOF' > /home/user/stats_engine/src/stats.c
#include "stats.h"
#include <math.h>

double calculate_variance(double* data, int n) {
    if (n <= 1) return 0.0;
    double sum = 0.0;
    double sum_sq = 0.0;
    for(int i = 0; i < n; i++) {
        sum += data[i];
        sum_sq += data[i] * data[i];
    }
    return (sum_sq - ((sum * sum) / n)) / (n - 1);
}
EOF

    cat << 'EOF' > /home/user/stats_engine/tests/test_main.c
#include <stdio.h>
#include <math.h>
#include "../src/stats.h"

int main() {
    double data[] = {1000000000.0, 1000000001.0, 1000000002.0};
    double var = calculate_variance(data, 3);

    // The sample variance of [x, x+1, x+2] is exactly 1.0
    if (fabs(var - 1.0) < 1e-5) {
        printf("Test passed.\n");
        return 0;
    } else {
        printf("Test failed. Expected 1.0, got %f\n", var);
        return 1;
    }
}
EOF

    cat << 'EOF' > /home/user/stats_engine/Makefile
CC = gcc
CFLAGS = -Wall -Wextra -I./src

all: run_tests

run_tests: tests/test_main.c src/stats.c
	$(CC) $(CFLAGS) -o run_tests tests/test_main.c src/stats.c

test: run_tests
	./run_tests

clean:
	rm -f run_tests
EOF

    chown -R user:user /home/user/stats_engine
    chmod -R 777 /home/user
