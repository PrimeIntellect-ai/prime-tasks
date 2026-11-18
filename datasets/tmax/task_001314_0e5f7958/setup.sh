#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

float *data;
int num_elements;
int num_threads;

float total_sum = 0.0f;
float total_sq_sum = 0.0f;

void* process_data(void* arg) {
    int tid = *(int*)arg;
    int chunk = num_elements / num_threads;
    int start = tid * chunk;
    int end = start + chunk;

    // Bug 1: Off-by-one / out-of-bounds causing segfault
    if (tid == num_threads - 1) {
        end = num_elements + 1000; 
    }

    for (int i = start; i < end; i++) {
        // Bug 2 & 3: Race condition and precision loss
        total_sum += data[i];
        total_sq_sum += data[i] * data[i];
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <num_elements> <num_threads>\n", argv[0]);
        return 1;
    }
    num_elements = atoi(argv[1]);
    num_threads = atoi(argv[2]);

    data = malloc(num_elements * sizeof(float));
    for(int i=0; i<num_elements; i++) {
        data[i] = 0.1f;
    }

    pthread_t threads[num_threads];
    int tids[num_threads];

    for (int i = 0; i < num_threads; i++) {
        tids[i] = i;
        pthread_create(&threads[i], NULL, process_data, &tids[i]);
    }

    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    float mean = total_sum / num_elements;
    float variance = (total_sq_sum / num_elements) - (mean * mean);

    printf("Sum: %.5f\n", total_sum);
    printf("Variance: %.5f\n", variance);

    free(data);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
