#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas

    mkdir -p /app
    cat << 'EOF' > /app/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[4096];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        if (strstr(buffer, "\\u0000") != NULL) {
            int *p = NULL; *p = 1;
        }
        char *ptr = buffer;
        while ((ptr = strstr(ptr, "\\uD")) != NULL || (ptr = strstr(ptr, "\\ud")) != NULL) {
            if ((ptr[3] >= '8' && ptr[3] <= 'B') || (ptr[3] >= '8' && ptr[3] <= 'b')) {
                if (ptr[6] == '\\' && ptr[7] == 'u' && (ptr[8] == 'D' || ptr[8] == 'd') && 
                    ((ptr[9] >= 'C' && ptr[9] <= 'F') || (ptr[9] >= 'c' && ptr[9] <= 'f'))) {
                    // valid surrogate pair
                } else {
                    int *p = NULL; *p = 1; // crash
                }
            }
            ptr++;
        }
    }
    return 0;
}
EOF
    gcc /app/validator.c -o /app/validator
    strip /app/validator
    rm /app/validator.c

    mkdir -p /opt/tests/clean_corpus
    mkdir -p /opt/tests/evil_corpus
    mkdir -p /home/user

    python3 -c '
import os, json, random
from datetime import datetime, timedelta

def generate_data(path, num_files, evil=False):
    for i in range(num_files):
        with open(f"{path}/file_{i}.jsonl", "w") as f:
            for j in range(50):
                is_evil = evil and random.random() < 0.2
                comment = f"Reading stable. [CODE: E-{random.randint(100,999)}]"
                if is_evil:
                    comment += random.choice(["\\uD83D", "\\u0000"])
                record = {
                    "timestamp": (datetime(2023, 1, 1) + timedelta(minutes=j)).isoformat(),
                    "sensor_id": f"sensor_{random.randint(1,3)}",
                    "reading": random.random() * 100,
                    "comment": comment
                }
                f.write(json.dumps(record) + "\n")

generate_data("/opt/tests/clean_corpus", 10, False)
generate_data("/opt/tests/evil_corpus", 10, True)

with open("/home/user/sample.jsonl", "w") as f:
    f.write("{\"timestamp\": \"2023-01-01T00:00:00\", \"sensor_id\": \"sensor_1\", \"reading\": 42.0, \"comment\": \"Reading stable. [CODE: E-123]\"}\n")
    f.write("{\"timestamp\": \"2023-01-01T00:01:00\", \"sensor_id\": \"sensor_1\", \"reading\": 43.0, \"comment\": \"Bad \\uD800 data\"}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
