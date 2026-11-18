#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/data /home/user/output /app

    # Create and compile the hasher binary
    cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <stdint.h>
int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    char *s = argv[1];
    uint32_t h = 0x5A5A5A5A;
    while(*s) {
        h = ((h << 5) + h) ^ (*s++);
    }
    printf("%08x\n", h);
    return 0;
}
EOF
    gcc -O2 /tmp/hasher.c -o /app/config_hasher
    strip /app/config_hasher
    rm /tmp/hasher.c

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import csv
import json
import random
from datetime import datetime, timedelta

def generate_data():
    csv_data = []
    json_data = []

    start_time = datetime(2023, 10, 1)

    for i in range(25000):
        dt = start_time + timedelta(seconds=random.randint(0, 86400 * 5))
        server_id = f"server_{random.randint(1, 10)}"
        val = f"config_{random.randint(1, 1000)}"
        csv_data.append([dt.strftime("%Y-%m-%d %H:%M:%S"), server_id, val])

        dt2 = start_time + timedelta(seconds=random.randint(0, 86400 * 5))
        server_id2 = f"server_{random.randint(1, 10)}"
        val2 = f"config_{random.randint(1, 1000)}"
        # Python 3.10+ datetime.timestamp() assumes local time if naive, 
        # but for dummy data consistency is fine as long as we treat it as UTC epoch.
        # Let's just use UTC explicitly.
        json_data.append({"time": int(dt2.timestamp()), "server": server_id2, "val": val2})

    with open('/home/user/data/configs.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "server_id", "config_val"])
        writer.writerows(csv_data)

    with open('/home/user/data/configs.json', 'w') as f:
        json.dump(json_data, f)

generate_data()
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
