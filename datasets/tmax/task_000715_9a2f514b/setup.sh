#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 gcc
    pip3 install pytest numpy opencv-python pandas scikit-learn

    mkdir -p /app

    # Generate video and sensor data
    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import pandas as pd

# Generate Video
out = cv2.VideoWriter('/app/experiment_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 25, (100, 100), isColor=False)
brightness_vals = []
for i in range(1500):
    b = int(100 + 50 * np.sin(i * 0.1))
    frame = np.full((100, 100), b, dtype=np.uint8)
    out.write(frame)
    brightness_vals.append(b)
out.release()

# Generate Sensor Data
sensor_data = []
for i in range(1500):
    timestamp_ms = i * 40
    b = brightness_vals[i]
    sensor_value = b * 2.5 + np.random.normal(0, 0.1)
    sensor_data.append((timestamp_ms, round(sensor_value, 4)))

df = pd.DataFrame(sensor_data, columns=['timestamp_ms', 'sensor_value'])
df.to_csv('/app/sensor_data.csv', index=False)
EOF
    python3 /tmp/generate_data.py

    # Create oracle C program
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ROWS 20000

typedef struct {
    long long ts;
    char val[256];
} Row;

Row sensor[MAX_ROWS];
int sensor_count = 0;

int main(int argc, char *argv[]) {
    if(argc != 3) return 1;
    FILE *f1 = fopen(argv[1], "r");
    FILE *f2 = fopen(argv[2], "r");
    if(!f1 || !f2) return 1;

    char line[1024];
    fgets(line, sizeof(line), f2);
    while(fgets(line, sizeof(line), f2)) {
        line[strcspn(line, "\r\n")] = 0;
        char *comma = strchr(line, ',');
        if(comma) {
            *comma = 0;
            long long ts = atoll(line);
            int found = 0;
            for(int i=0; i<sensor_count; i++) {
                if(sensor[i].ts == ts) { found = 1; break; }
            }
            if(!found && sensor_count < MAX_ROWS) {
                sensor[sensor_count].ts = ts;
                strcpy(sensor[sensor_count].val, comma+1);
                sensor_count++;
            }
        }
    }

    fgets(line, sizeof(line), f1);
    long long seen_ts[MAX_ROWS];
    int seen_count = 0;

    while(fgets(line, sizeof(line), f1)) {
        line[strcspn(line, "\r\n")] = 0;
        char *first_comma = strchr(line, ',');
        if(!first_comma) continue;
        char *second_comma = strchr(first_comma+1, ',');
        if(!second_comma) continue;

        long long ts = atoll(first_comma+1);
        int already_seen = 0;
        for(int i=0; i<seen_count; i++) {
            if(seen_ts[i] == ts) { already_seen = 1; break; }
        }
        if(already_seen) continue;

        if(seen_count < MAX_ROWS) seen_ts[seen_count++] = ts;

        for(int i=0; i<sensor_count; i++) {
            if(sensor[i].ts == ts) {
                printf("%lld,%s,%s\n", ts, second_comma+1, sensor[i].val);
                break;
            }
        }
    }
    fclose(f1);
    fclose(f2);
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_join_stats
    chmod 755 /app/oracle_join_stats

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
