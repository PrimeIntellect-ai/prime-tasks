#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /home/user/data
    mkdir -p /app

    # Create and compile log_decoder
    cat << 'EOF' > /app/log_decoder.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    char* input = argv[1];
    float temp = 30.0 + (strlen(input) % 40) + (strlen(input) % 10) * 0.5;
    printf("STATUS=OK|CPU_TEMP=%.1f|MEM_USAGE=80\n", temp);
    return 0;
}
EOF
    gcc -O3 -s /app/log_decoder.c -o /app/log_decoder
    rm /app/log_decoder.c

    # Generate telemetry.csv
    cat << 'EOF' > /tmp/gen_csv.py
import csv
import binascii
import random

random.seed(42)

with open('/home/user/data/telemetry.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'source_ip', 'raw_payload'])

    hours = ["2023-10-24T14", "2023-10-24T15", "2023-10-24T16"]
    for hour in hours:
        for m in range(0, 60, 5):
            ts = f"{hour}:{m:02d}:00Z"
            payload = f"System log at minute {m} with some random padding {random.randint(1000,9999)}"
            hex_payload = binascii.hexlify(payload.encode('utf-8')).decode('ascii')
            writer.writerow([ts, '192.168.1.1', hex_payload])
EOF
    python3 /tmp/gen_csv.py
    rm /tmp/gen_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
