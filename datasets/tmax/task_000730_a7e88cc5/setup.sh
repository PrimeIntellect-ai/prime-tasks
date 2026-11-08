#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/log_generator.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <unistd.h>

#define MAX_FILE_SIZE 524288

struct __attribute__((packed)) LogHeader {
    uint8_t magic[2];
    uint64_t timestamp_us;
    uint8_t severity;
    uint16_t msg_len;
};

int main(int argc, char *argv[]) {
    int duration = 30;
    int seed = 42;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            seed = atoi(argv[++i]);
        }
    }
    srand(seed);

    char dir[] = "/home/user/raw_logs";
    char live_path[256];
    snprintf(live_path, sizeof(live_path), "%s/live.log", dir);

    FILE *f = fopen(live_path, "wb");
    if (!f) return 1;

    int total_records = 100000;
    size_t current_size = 0;

    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t start_time = (uint64_t)tv.tv_sec * 1000000ULL + tv.tv_usec;

    int sleep_us = 0;
    if (duration > 0 && total_records > 0) {
        sleep_us = (duration * 1000000) / total_records;
    }

    for (int i = 0; i < total_records; i++) {
        struct LogHeader h;
        h.magic[0] = 0xBE;
        h.magic[1] = 0xEF;
        h.timestamp_us = start_time + i * 1000ULL;
        h.severity = rand() % 6;

        char msg[256];
        int msg_len = snprintf(msg, sizeof(msg), "Log message %d with some extra padding to make it realistic.", i);
        h.msg_len = msg_len;

        size_t record_size = sizeof(h) + msg_len;
        if (current_size + record_size > MAX_FILE_SIZE) {
            fclose(f);
            char archive_path[256];
            snprintf(archive_path, sizeof(archive_path), "%s/archived_%llu.log", dir, (unsigned long long)h.timestamp_us);
            rename(live_path, archive_path);
            f = fopen(live_path, "wb");
            if (!f) return 1;
            current_size = 0;
        }

        fwrite(&h, 1, sizeof(h), f);
        fwrite(msg, 1, msg_len, f);
        current_size += record_size;
        fflush(f);

        if (sleep_us > 0) {
            usleep(sleep_us);
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/log_generator.c -o /app/log_generator
    strip /app/log_generator
    rm /app/log_generator.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/raw_logs
    chmod -R 777 /home/user
