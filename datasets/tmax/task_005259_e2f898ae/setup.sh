#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc
    pip3 install pytest

    mkdir -p /app/data /app/test

    # Create C source for legacy encoder
    cat << 'EOF' > /app/encoder.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    float vec[32] = {0};
    if (argc < 2) {
        for(int i=0; i<31; i++) printf("0.0,");
        printf("0.0\n");
        return 0;
    }
    char *str = argv[1];
    int len = strlen(str);
    if (len == 0) {
        for(int i=0; i<31; i++) printf("0.0,");
        printf("0.0\n");
        return 0;
    }
    for (int i = 0; i < len; i++) {
        if (!isalnum(str[i]) && str[i] != ' ') {
            for(int j=0; j<31; j++) printf("0.0,");
            printf("0.0\n");
            return 0;
        }
    }
    unsigned int seed = 12345;
    for (int i = 0; i < len; i++) {
        seed = seed * 1664525 + 1013904223 + str[i];
    }
    for (int i = 0; i < 32; i++) {
        seed = seed * 1664525 + 1013904223;
        vec[i] = (float)(seed % 10000) / 10000.0f;
    }
    for(int i=0; i<31; i++) printf("%f,", vec[i]);
    printf("%f\n", vec[31]);
    return 0;
}
EOF

    gcc -O2 -s /app/encoder.c -o /app/legacy_encoder
    rm /app/encoder.c

    # Generate data and reference
    cat << 'EOF' > /app/setup_data.py
import csv
import json
import subprocess
import re

data = [
    {"user_id": "u1", "event_type": "view", "item_name": "Apple!", "timestamp": "2023-01-01T10:00:00Z"},
    {"user_id": "u1", "event_type": "buy", "item_name": "Banana", "timestamp": "2023-01-01T10:05:00Z"},
    {"user_id": "u2", "event_type": "view", "item_name": "Cherry pie?", "timestamp": "2023-01-01T10:01:00Z"},
    {"user_id": "u2", "event_type": "view", "item_name": "Dates-", "timestamp": "2023-01-01T10:02:00Z"},
    {"user_id": "u3", "event_type": "buy", "item_name": "Eggplant", "timestamp": "2023-01-01T10:00:00Z"},
]

with open('/app/data/events.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["user_id", "event_type", "item_name", "timestamp"])
    writer.writeheader()
    writer.writerows(data)

users = {}
for row in data:
    users.setdefault(row['user_id'], []).append(row)

with open('/app/test/reference.jsonl', 'w') as f:
    for uid, rows in users.items():
        rows.sort(key=lambda x: x['timestamp'])
        items = [r['item_name'] for r in rows]
        concat = " ".join(items)
        sanitized = re.sub(r'[^a-zA-Z0-9 ]', '', concat)

        out = subprocess.check_output(['/app/legacy_encoder', sanitized]).decode('utf-8').strip()
        vec = [float(x) for x in out.split(',')]
        f.write(json.dumps({"user_id": uid, "embedding": vec}) + "\n")
EOF

    python3 /app/setup_data.py
    rm /app/setup_data.py

    chmod -R 755 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
