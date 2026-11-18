#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc tshark tcpdump python3-scapy
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create Git Repo with secret
    mkdir -p /home/user/math_stat_repo
    cd /home/user/math_stat_repo
    git init

    cat << 'EOF' > config.h
#define SECRET_COEFF 42.42
EOF

    cat << 'EOF' > stat_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include "config.h"

#define NUM_THREADS 4

double total_sum = 0.0;
double secret_coeff = SECRET_COEFF;
double *values;
int num_values = 0;

void* compute_sum(void* arg) {
    int thread_id = *(int*)arg;
    int chunk_size = num_values / NUM_THREADS;
    int start = thread_id * chunk_size;
    int end = (thread_id == NUM_THREADS - 1) ? num_values : start + chunk_size;

    for (int i = start; i < end; i++) {
        // Race condition
        double temp = total_sum;
        usleep(10); // force context switch to guarantee race condition
        total_sum = temp + (values[i] * secret_coeff);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    // legacy main
    return 0;
}
EOF

    git add config.h stat_calc.c
    git config user.email "dev@example.com"
    git config user.name "Dev"
    git commit -m "Initial commit with math logic"

    # 2. Modify to current buggy state (remove secret)
    rm config.h

    cat << 'EOF' > stat_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>

#define NUM_THREADS 4

double total_sum = 0.0;
double secret_coeff = 1.0;
double *values;
int num_values = 0;

void* compute_sum(void* arg) {
    int thread_id = *(int*)arg;
    int chunk_size = num_values / NUM_THREADS;
    int start = thread_id * chunk_size;
    int end = (thread_id == NUM_THREADS - 1) ? num_values : start + chunk_size;

    for (int i = start; i < end; i++) {
        // Race condition
        double temp = total_sum;
        usleep(10); // force context switch to guarantee race condition
        total_sum = temp + (values[i] * secret_coeff);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <secret_coeff> <file_with_values>\n", argv[0]);
        return 1;
    }
    secret_coeff = atof(argv[1]);

    FILE *f = fopen(argv[2], "r");
    if(!f) return 1;

    values = malloc(10000 * sizeof(double));
    while (fscanf(f, "%lf", &values[num_values]) == 1) {
        num_values++;
    }
    fclose(f);

    pthread_t threads[NUM_THREADS];
    int thread_ids[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, compute_sum, &thread_ids[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("%.5f\n", total_sum);
    free(values);
    return 0;
}
EOF

    git add stat_calc.c
    git rm config.h
    git commit -m "Refactor: remove hardcoded config, read inputs from args"

    # 3. Create PCAP file
    cd /home/user
    cat << 'EOF' > generate_pcap.py
from scapy.all import *

packets = []
# Values 1.0 to 100.0
# Sum = 5050.0
for i in range(1, 101):
    payload = f"{float(i)}\n".encode('ascii')
    pkt = IP(dst="127.0.0.1")/UDP(dport=8080, sport=12345)/Raw(load=payload)
    packets.append(pkt)

    # Add some noise on other ports
    noise_pkt = IP(dst="127.0.0.1")/UDP(dport=9090)/Raw(load=b"ignore me")
    packets.append(noise_pkt)

wrpcap("traffic.pcap", packets)
EOF
    python3 generate_pcap.py
    rm generate_pcap.py

    chown -R user:user /home/user/math_stat_repo /home/user/traffic.pcap
    chmod -R 777 /home/user
