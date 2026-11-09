#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/events.log
1620000000,200,450,48656c6c6f
1620000001,200,460,576f726c64
1620000002,200,440,414243
1620000003,200,470,4445464
1620000004,500,52000,4572726f72
1620000005,200,455,4f4b
1620000006,503,61000,54696d656f7574
1620000007,200,445,41
1620000008,200,465,424
EOF

    cat << 'EOF' > /home/user/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

unsigned char decode_hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

typedef struct {
    long timestamp;
    int status;
    int resp_time;
    char* decoded_payload;
} LogEntry;

int main(int argc, char** argv) {
    FILE* f = fopen("/home/user/events.log", "r");
    if (!f) {
        perror("Failed to open log file");
        return 1;
    }

    char line[256];
    LogEntry entries[100];
    int count = 0;

    int sum = 0;
    int sum_sq = 0; // BUG: 32-bit integer overflow for large resp_time^2 (e.g., 61000^2 = 3.7 billion)

    while(fgets(line, sizeof(line), f)) {
        long ts;
        int status, resp_time;
        char payload[128];

        if (sscanf(line, "%ld,%d,%d,%127s", &ts, &status, &resp_time, payload) == 4) {
            int len = strlen(payload);

            // BUG: Handles odd lengths poorly, reading out of bounds.
            char* decoded = malloc(len / 2 + 2);
            for(int i = 0; i < len; i += 2) {
                decoded[i/2] = (decode_hex(payload[i]) << 4) | decode_hex(payload[i+1]);
            }
            decoded[len/2] = '\0';

            entries[count].timestamp = ts;
            entries[count].status = status;
            entries[count].resp_time = resp_time;
            entries[count].decoded_payload = decoded;

            sum += resp_time;
            sum_sq += resp_time * resp_time;
            count++;
        }
    }
    fclose(f);

    if (count == 0) return 0;

    double average = (double)sum / count;
    // When sum_sq overflows, variance becomes negative, and sqrt(variance) is NaN.
    double variance = ((double)sum_sq / count) - (average * average);
    double stddev = sqrt(variance);

    double threshold = average + 2 * stddev;

    for (int i = 0; i < count; i++) {
        if (entries[i].resp_time > threshold) {
            printf("Anomaly detected at %ld: %d ms\n", entries[i].timestamp, entries[i].resp_time);
        }
        free(entries[i].decoded_payload);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
