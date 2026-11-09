#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.c
#include <stdio.h>
#include <stdlib.h>

// LCG for deterministic noise
unsigned int seed = 42;
double my_rand() {
    seed = (1103515245 * seed + 12345) % 2147483648;
    return (double)seed / 2147483648.0;
}

int main() {
    int width = 20, height = 20;
    int steps = 50;

    // BUG 1: Allocating an array of doubles instead of double pointers
    double **grid = malloc(height * sizeof(double));
    for(int i=0; i<height; i++) {
        // BUG 2: Allocating 1 double instead of `width` doubles
        grid[i] = malloc(sizeof(double)); 
    }

    for(int i=0; i<height; i++) {
        for(int j=0; j<width; j++) {
            grid[i][j] = 100.0;
        }
    }

    double decay = 0.05;
    for(int t=0; t<steps; t++) {
        double sum = 0;
        for(int i=0; i<height; i++) {
            for(int j=0; j<width; j++) {
                grid[i][j] = grid[i][j] * (1.0 - decay);
                double noise = (my_rand() - 0.5) * 2.0; 
                sum += grid[i][j] + noise;
            }
        }
        printf("%d,%.4f\n", t, sum / (width*height));
    }

    // Cleanup omitted
    return 0;
}
EOF

    cat << 'EOF' > /home/user/baseline.csv
0,94.9961
1,90.2676
2,85.7483
3,81.4589
4,77.3872
EOF

    chmod -R 777 /home/user
