#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go build-essential curl
    pip3 install pytest

    mkdir -p /home/user/legacy /home/user/api

    cat << 'EOF' > /home/user/legacy/solver.h
#ifndef SOLVER_H
#define SOLVER_H

int solve_knapsack(int* weights, int* values, int n, int capacity);

#endif
EOF

    cat << 'EOF' > /home/user/legacy/solver.c
#include "solver.h"

int solve_knapsack(int* weights, int* values, int n, int capacity) {
    // BUG: Hardcoded small size, causes stack overflow when capacity > 50
    int dp[50] = {0}; 

    for (int i = 0; i < n; i++) {
        for (int w = capacity; w >= weights[i]; w--) {
            if (dp[w - weights[i]] + values[i] > dp[w]) {
                dp[w] = dp[w - weights[i]] + values[i];
            }
        }
    }
    return dp[capacity];
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
