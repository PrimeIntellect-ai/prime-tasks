#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/logs/collector.log
[2023-10-27T08:12:01Z] INFO: Collector started
[2023-10-27T08:13:45Z] WARN: High latency on sensor 4
[2023-10-27T08:14:12Z] INFO: Heartbeat OK
EOF

    cat << 'EOF' > /home/user/logs/processor.log
1698394441 INFO: Processor init
1698394490 DEBUG: Processing batch 1
1698394500 ERROR: Memory threshold exceeded
1698394514 FATAL_CRASH: Segmentation fault in WAL sync
EOF

    cat << 'EOF' > /home/user/src/recover.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "utils.h"

#pragma pack(push, 1)
typedef struct {
    uint32_t timestamp;
    uint32_t sensor_id;
    float temp_c;
} Record;
#pragma pack(pop)

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.wal> <output.csv>\n", argv[0]);
        return 1;
    }

    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "w");
    if (!fout) return 1;

    fprintf(fout, "timestamp,sensor_id,temp_f\n");

    Record rec;
    while (fread(&rec, sizeof(Record), 1, fin) == 1) {
        float temp_f = celsius_to_fahrenheit(rec.temp_c);
        float variance = calculate_variance(rec.temp_c); 
        fprintf(fout, "%u,%u,%.2f\n", rec.timestamp, rec.sensor_id, temp_f);
    }

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/utils.h
#ifndef UTILS_H
#define UTILS_H

float celsius_to_fahrenheit(float c);
float calculate_variance(float val);

#endif
EOF

    cat << 'EOF' > /home/user/src/utils.c
#include "utils.h"
#include <math.h>

float celsius_to_fahrenheit(float c) {
    return (c * 5.0f / 9.0f) + 32.0f;
}

float calculate_variance(float val) {
    return pow(val, 2.0f) / sqrt(val + 1.0f);
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
CC=gcc
CFLAGS=-Wall -Wextra

all: recover

recover: recover.o utils.o
	$(CC) $(CFLAGS) -o recover recover.o utils.o 

recover.o: recover.c
	$(CC) $(CFLAGS) -c recover.c

utils.o: utils.c
	$(CC) $(CFLAGS) -c utils.c

clean:
	rm -f *.o recover
EOF

    cat << 'EOF' > /tmp/gen_wal.py
import struct

records = [
    (1698394400, 1, 20.0),
    (1698394410, 2, 25.0),
    (1698394420, 1, 22.5),
    (1698394430, 3, 30.0),
]

with open('/home/user/data/sensor.wal', 'wb') as f:
    for ts, sid, temp in records:
        f.write(struct.pack('<IIf', ts, sid, temp))
EOF
    python3 /tmp/gen_wal.py
    rm /tmp/gen_wal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
