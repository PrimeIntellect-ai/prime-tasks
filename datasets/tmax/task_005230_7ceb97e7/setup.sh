#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/ml_data
    cat << 'EOF' > /home/user/ml_data/network_mc.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t state = 1;

uint32_t xorshift32() {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

double rand_float() {
    return (double)xorshift32() / 4294967296.0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int seed = atoi(argv[1]);
    state = seed;

    int n = 50;
    int adj[50][50] = {0};
    int degrees[50] = {0};

    // Generate graph (Erdos-Renyi p=0.3)
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            if (rand_float() < 0.3) {
                adj[i][degrees[i]++] = j;
                adj[j][degrees[j]++] = i;
            }
        }
    }

    // Monte Carlo Random Walk from node 0 to node n-1
    int num_walks = 1000;
    long total_steps = 0;

    for (int w = 0; w < num_walks; w++) {
        int curr = 0;
        int steps = 0;
        while (curr != n - 1 && steps < 1000) {
            if (degrees[curr] == 0) break; // dead end
            int next_idx = xorshift32() % degrees[curr];
            curr = adj[curr][next_idx];
            steps++;
        }
        total_steps += steps;
    }

    printf("%d,%.2f\n", seed, (double)total_steps / num_walks);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
