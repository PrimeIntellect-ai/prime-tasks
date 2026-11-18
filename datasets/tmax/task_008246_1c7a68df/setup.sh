#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mc_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long N = atol(argv[1]);
    long in_circle = 0;

    // Fixed seed for pseudo-predictable workload (though execution time varies due to system load)
    srand(42); 

    clock_t start = clock();
    for(long i=0; i<N; i++) {
        double x = (double)rand()/RAND_MAX;
        double y = (double)rand()/RAND_MAX;
        if (x*x + y*y <= 1.0) {
            in_circle++;
        }
    }
    clock_t end = clock();

    double time_spent = (double)(end - start) / CLOCKS_PER_SEC;
    printf("%f\n", time_spent);
    return 0;
}
EOF

    chmod -R 777 /home/user
