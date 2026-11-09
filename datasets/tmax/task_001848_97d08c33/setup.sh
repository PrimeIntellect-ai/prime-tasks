#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make time gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/fastlog_etl-1.0.0/src
    mkdir -p /app/fastlog_etl-1.0.0/bin

    cat << 'EOF' > /app/fastlog_etl-1.0.0/Makefile
CC = gcc
CFLAGS = -Wall -O0
TARGET = bin/fastlog_etl

all: $(TARGET)

$(TARGET): src/process.c
	$(CC) $(CFLAGS) -o $(TARGET) src/process.c

clean:
	rm -f $(TARGET)
EOF

    cat << 'EOF' > /app/fastlog_etl-1.0.0/src/process.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char endpoint[64];
    int latency;
} Record;

void bubble_sort(Record* arr, int n) {
    for (int i = 0; i < n-1; i++) {
        for (int j = 0; j < n-i-1; j++) {
            if (strcmp(arr[j].endpoint, arr[j+1].endpoint) > 0) {
                Record temp = arr[j];
                arr[j] = arr[j+1];
                arr[j+1] = temp;
            }
        }
    }
}

int main() {
    Record* records = malloc(200000 * sizeof(Record));
    int count = 0;
    char line[256];

    while (fgets(line, sizeof(line), stdin)) {
        char* ts = strtok(line, ",");
        char* ep = strtok(NULL, ",");
        char* lat = strtok(NULL, "\n");
        if (ts && ep && lat) {
            strcpy(records[count].endpoint, ep);
            records[count].latency = atoi(lat);
            count++;
        }
    }

    // Perturbation: using O(N^2) sort
    bubble_sort(records, count);

    if (count == 0) return 0;

    char current_ep[64];
    strcpy(current_ep, records[0].endpoint);
    int ep_count = 0;
    long total_lat = 0;

    for (int i = 0; i < count; i++) {
        if (strcmp(records[i].endpoint, current_ep) == 0) {
            ep_count++;
            total_lat += records[i].latency;
        } else {
            printf("%s,%d,%ld\n", current_ep, ep_count, total_lat / ep_count);
            strcpy(current_ep, records[i].endpoint);
            ep_count = 1;
            total_lat = records[i].latency;
        }
    }
    printf("%s,%d,%ld\n", current_ep, ep_count, total_lat / ep_count);

    free(records);
    return 0;
}
EOF

    cat << 'EOF' > /tmp/gen_logs.py
import random
endpoints = ["/api/v1/users", "/api/v1/auth", "/api/v1/data", "/api/v1/settings", "/health"]
with open("/home/user/api_logs.csv", "w") as f:
    for i in range(50000):
        ep = random.choice(endpoints)
        lat = random.randint(10, 500)
        f.write(f"167990{i:04d},{ep},{lat}\n")
EOF
    python3 /tmp/gen_logs.py

    chmod -R 777 /app/fastlog_etl-1.0.0
    chmod -R 777 /home/user
