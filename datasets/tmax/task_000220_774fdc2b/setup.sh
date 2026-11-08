#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    # Create C program for imputer_oracle
    cat << 'EOF' > /app/imputer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *input = argv[1];
    double vals[1000];
    int is_nan[1000];
    int count = 0;
    char *token = strtok(input, " ");
    while(token != NULL && count < 1000) {
        if (strcmp(token, "NaN") == 0) {
            vals[count] = 0.0;
            is_nan[count] = 1;
        } else {
            vals[count] = atof(token);
            is_nan[count] = 0;
        }
        count++;
        token = strtok(NULL, " ");
    }
    for(int i=0; i<count; i++) {
        if(is_nan[i]) {
            int prev = i-1;
            while(prev >= 0 && is_nan[prev]) prev--;
            int next = i+1;
            while(next < count && is_nan[next]) next++;
            double v1 = (prev >= 0) ? vals[prev] : 0.0;
            double v2 = (next < count) ? vals[next] : 0.0;
            if(prev >= 0 && next < count) vals[i] = (v1+v2)/2.0;
            else if(prev >= 0) vals[i] = v1;
            else if(next < count) vals[i] = v2;
        }
    }
    for(int i=0; i<count; i++) {
        printf("%g ", vals[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /app/imputer.c -o /app/imputer_oracle
    strip /app/imputer_oracle
    chmod +x /app/imputer_oracle
    rm /app/imputer.c

    # Generate raw sensor data
    cat << 'EOF' > /app/setup.py
import json
import random

random.seed(42)
with open('/app/raw_sensor_data.jsonl', 'w') as f:
    for i in range(1, 501):
        readings = []
        for _ in range(10):
            if random.random() < 0.2:
                readings.append(None)
            else:
                readings.append(round(random.uniform(10.0, 50.0), 2))
        record = {
            "id": i,
            "messy_log": f"Log_entry #{i}! Error: {random.choice(['None', 'Temp', 'Press'])}.",
            "readings": readings
        }
        f.write(json.dumps(record) + '\n')
EOF

    python3 /app/setup.py
    rm /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
