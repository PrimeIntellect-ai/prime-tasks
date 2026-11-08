#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb libc6-dev
    pip3 install pytest

    mkdir -p /home/user/incident_1029/lib
    cd /home/user/incident_1029

    # Create the custom library
    cat << 'EOF' > lib/custommath.c
double custom_multiply(double a, double b) {
    return a * b;
}
EOF
    gcc -shared -o lib/libcustommath.so -fPIC lib/custommath.c

    # Create main.c
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "cost_calc.h"

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <node> <depth>\n", argv[0]);
        return 1;
    }
    int node = atoi(argv[1]);
    int depth = atoi(argv[2]);

    double cost = compute_path_cost(node, depth);
    printf("%.4f\n", cost);
    return 0;
}
EOF

    # Create header
    cat << 'EOF' > cost_calc.h
#ifndef COST_CALC_H
#define COST_CALC_H
double compute_path_cost(int node, int depth);
extern double custom_multiply(double a, double b);
#endif
EOF

    # Create buggy cost_calc.c
    cat << 'EOF' > cost_calc.c
#include "cost_calc.h"

double compute_path_cost(int node, int depth) {
    if (depth == 0) {
        // Bug 1: Adds instead of using custom_multiply
        return node + 1.5; 
    }

    int next_node = (node * 3) % 17;
    // Bug 2: depth + 1 causes infinite recursion / stack overflow
    double next_cost = compute_path_cost(next_node, depth + 1);

    return (next_cost / 2.0) + node;
}
EOF

    # Create buggy Makefile
    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -g
LDFLAGS=-lcustommath

route_optimizer: main.o cost_calc.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

main.o: main.c cost_calc.h
	$(CC) $(CFLAGS) -c main.c

cost_calc.o: cost_calc.c cost_calc.h
	$(CC) $(CFLAGS) -c cost_calc.c

clean:
	rm -f *.o route_optimizer
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
