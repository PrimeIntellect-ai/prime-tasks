#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq gawk curl binutils
    pip3 install pytest flask

    # Create the stripped binary
    mkdir -p /app
    cat << 'EOF' > /app/sensor_decoder.c
#include <stdio.h>
int main(int argc, char *argv[]) {
    if (argc > 1) {
        printf("[{\"timestamp\": \"2023-01-05T10:00:00\", \"sensor\": \"SENS-01\", \"reading\": 100.5}]\n");
    }
    return 0;
}
EOF
    gcc -o /app/sensor_decoder /app/sensor_decoder.c
    strip /app/sensor_decoder
    rm /app/sensor_decoder.c

    # Create raw data directories and files
    mkdir -p /home/user/raw_data/csv_data
    mkdir -p /home/user/raw_data/json_data
    mkdir -p /home/user/raw_data/log_data
    mkdir -p /home/user/raw_data/dat_data

    # CSV
    cat << 'EOF' > /home/user/raw_data/csv_data/readings1.csv
date,time,sensor,reading
2023-01-01,10:00:00,SENS-01,12.3
2023-01-01,10:05:00,SENS-02,8.4
EOF

    # JSON
    cat << 'EOF' > /home/user/raw_data/json_data/readings1.json
[
  {"ts": "2023-01-02T10:00:00", "sensor_id": "SENS-01", "val": 15.0},
  {"ts": "2023-01-02T10:05:00", "sensor_id": "SENS-02", "val": 9.1}
]
EOF

    # LOG
    cat << 'EOF' > /home/user/raw_data/log_data/readings1.log
---RECORD---
TS: 2023-01-03T10:00:00
ID: SENS-01
VAL: 20.1
---END---
---RECORD---
TS: 2023-01-03T10:05:00
ID: SENS-02
VAL: 11.2
---END---
EOF

    # DAT
    echo -n -e '\x00\x01\x02\x03' > /home/user/raw_data/dat_data/readings1.dat

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
