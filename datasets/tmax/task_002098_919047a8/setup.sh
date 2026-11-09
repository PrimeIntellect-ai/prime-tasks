#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb valgrind libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/simulation.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <math.h>
#include <assert.h>

#define NUM_THREADS 4
#define NUM_RECORDS 1000000

double global_stddev_sum = 0.0;
pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

void* process_data(void* arg) {
    double sum = 0.0;
    double sum_sq = 0.0;
    int N = NUM_RECORDS;

    // Simulate query result data that is uniform but large, 
    // causing catastrophic cancellation in the naive variance formula.
    for(int i = 0; i < N; i++) {
        double val = 10000.1;
        sum += val;
        sum_sq += val * val;
    }

    double mean = sum / N;
    // NUMERICAL INSTABILITY: Due to floating point precision, this can result in a tiny negative number.
    double variance = (sum_sq / N) - (mean * mean);

    // The negative variance causes sqrt() to return NaN.
    double stddev = sqrt(variance);

    // Fails here because stddev is NaN
    assert(!isnan(stddev)); 

    // RACE CONDITION: global_stddev_sum is updated without acquiring the mutex lock
    global_stddev_sum += stddev;

    return NULL;
}

int main() {
    pthread_t threads[NUM_THREADS];

    for(int i = 0; i < NUM_THREADS; i++) {
        pthread_create(&threads[i], NULL, process_data, NULL);
    }

    for(int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    FILE *f = fopen("/home/user/results.log", "w");
    if(f) {
        fprintf(f, "Total StdDev Sum: %.6f\n", global_stddev_sum);
        fclose(f);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
