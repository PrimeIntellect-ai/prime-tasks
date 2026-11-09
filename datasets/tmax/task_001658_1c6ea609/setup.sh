#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest pandas pyarrow

    mkdir -p /app/data

    # Create and compile anonymizer
    cat << 'EOF' > /tmp/anonymizer.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <openssl/sha.h>

int main() {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        unsigned char hash[SHA256_DIGEST_LENGTH];
        SHA256((unsigned char*)line, strlen(line), hash);
        for(int i = 0; i < 8; i++) {
            printf("%02x", hash[i]);
        }
        printf("\n");
        fflush(stdout);
        usleep(5000); // 5ms delay per record
    }
    return 0;
}
EOF
    gcc -O3 /tmp/anonymizer.c -o /app/anonymizer -lcrypto
    strip /app/anonymizer
    rm /tmp/anonymizer.c

    # Generate data
    python3 -c '
import os
import random
import datetime
import csv

os.makedirs("/app/data", exist_ok=True)

event_types = ["video_stream", "audio_stream", "UI_click", "background_sync"]
users = [f"user{i}@example.com" for i in range(1000)]

start_date = datetime.datetime(2023, 10, 1)

for file_idx in range(50):
    filename = f"/app/data/activity_log_{file_idx:02d}.csv"
    with open(filename, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "user_id", "event_type", "duration_ms"])
        for _ in range(10000):
            dt = start_date + datetime.timedelta(days=random.randint(0, 30), seconds=random.randint(0, 86400))
            ts = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            user = random.choice(users)
            ev = random.choice(event_types)
            dur = round(random.uniform(1000.0, 300000.0), 2)
            writer.writerow([ts, user, ev, dur])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
