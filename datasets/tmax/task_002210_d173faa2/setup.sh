#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_svc

    cat << 'EOF' > /home/user/sensor_data.csv
ID,TIMESTAMP,VALUE,STATUS
101,1700000000123456,42.5,OK
102,1700000000223456,43.1,OK
103,1700000000323456,41.9,
104,1700000000423456,44.2,OK
EOF

    cat << 'EOF' > /home/user/telemetry_svc/Makefile
CC=gcc
CFLAGS=-g -Wall

parser_svc: main.o stats.o
	$(CC) $(CFLAGS) -o parser_svc main.o stats.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

stats.o: stats.c
	$(CC) $(CFLAGS) -c stats.c

clean:
	rm -f *.o parser_svc
EOF

    cat << 'EOF' > /home/user/telemetry_svc/stats.h
#ifndef STATS_H
#define STATS_H

double calculate_baseline(double val);

#endif
EOF

    cat << 'EOF' > /home/user/telemetry_svc/stats.c
#include "stats.h"
#include <math.h>

double calculate_baseline(double val) {
    // Arbitrary math function requiring libm
    return sqrt(val * val);
}
EOF

    cat << 'EOF' > /home/user/telemetry_svc/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "stats.h"

#define MAX_LINE 256

typedef struct {
    int id;
    float timestamp; // BUG: Precision loss. Should be uint64_t
    double value;
    char status[16];
} SensorRecord;

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.csv> <output.csv>\n", argv[0]);
        return 1;
    }

    FILE *in = fopen(argv[1], "r");
    if (!in) {
        perror("Failed to open input");
        return 1;
    }

    FILE *out = fopen(argv[2], "w");
    if (!out) {
        perror("Failed to open output");
        fclose(in);
        return 1;
    }

    char line[MAX_LINE];
    // Read header
    if (fgets(line, MAX_LINE, in)) {
        fprintf(out, "%s", line);
    }

    while (fgets(line, MAX_LINE, in)) {
        SensorRecord rec;
        line[strcspn(line, "\r\n")] = 0;

        char *token = strtok(line, ",");
        if (!token) continue;
        rec.id = atoi(token);

        token = strtok(NULL, ",");
        if (!token) continue;
        // BUG: Parsing as float
        rec.timestamp = atof(token);

        token = strtok(NULL, ",");
        if (!token) continue;
        rec.value = atof(token);

        token = strtok(NULL, ",");
        // BUG: Segfault if token is NULL (edge case where STATUS is empty)
        strcpy(rec.status, token);

        double baseline = calculate_baseline(rec.value);

        // BUG: Outputting as float (typically %f will print rounded value)
        fprintf(out, "%d,%.0f,%.1f,%s\n", rec.id, rec.timestamp, baseline, rec.status);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
