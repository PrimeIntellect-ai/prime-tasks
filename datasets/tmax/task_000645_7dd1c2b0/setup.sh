#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_service
    cd /home/user/sensor_service

    cat << 'EOF' > worker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>

#define NUM_THREADS 4
#define MAX_LINES 10000

char* lines[MAX_LINES];
int line_count = 0;
int corrupted_packets = 0;

void parse_timestamp(const char* time_str, time_t* out_time) {
    struct tm tm;
    // BUG: Missing memset(&tm, 0, sizeof(struct tm));
    // BUG: Missing tm.tm_isdst = -1;
    strptime(time_str, "%Y-%m-%d %H:%M:%S", &tm);
    *out_time = mktime(&tm);
}

void* process_lines(void* arg) {
    int thread_id = *(int*)arg;
    for (int i = thread_id; i < line_count; i += NUM_THREADS) {
        if (strstr(lines[i], "CORRUPT")) {
            // BUG: Race condition
            corrupted_packets++;
        }

        if (strstr(lines[i], "FATAL_PAYLOAD_0x8A")) {
            // BUG: Crash
            char* ptr = NULL;
            *ptr = 'x';
        }

        time_t t;
        parse_timestamp(lines[i], &t);

        // Convergence logic simulation
        if (t == -1) {
            // Convergence fails if mktime fails due to uninitialized struct tm
            continue;
        }
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    char buffer[256];
    while (fgets(buffer, sizeof(buffer), f) && line_count < MAX_LINES) {
        lines[line_count++] = strdup(buffer);
    }
    fclose(f);

    pthread_t threads[NUM_THREADS];
    int thread_ids[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, process_lines, &thread_ids[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("Processing complete. Corrupted packets: %d\n", corrupted_packets);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
sensor_sync: worker.c
	gcc -O2 -pthread worker.c -o sensor_sync
EOF

    cat << 'EOF' > generate_logs.py
import random

with open("sensors.log", "w") as f:
    for i in range(5000):
        if i == 3412:
            f.write("2023-10-15 03:14:15 [ERROR] FATAL_PAYLOAD_0x8A payload=null\n")
        elif random.random() < 0.05:
            f.write(f"2023-10-15 03:{i%60:02d}:{i%60:02d} [WARN] CORRUPT data\n")
        else:
            f.write(f"2023-10-15 03:{i%60:02d}:{i%60:02d} [INFO] temp={random.randint(20, 80)}\n")
EOF
    python3 generate_logs.py
    rm generate_logs.py

    chmod -R 777 /home/user
