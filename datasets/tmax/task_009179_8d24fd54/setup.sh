#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_b.txt
S04,2023-10-01T12:05:00Z,24.0
S05,2023-10-01T12:15:00Z,19.5°C
S06,2023-10-01T12:15:00,19.5
S07,2023-10-01T12:20:00Z,20.0
EOF
    iconv -f UTF-8 -t ISO-8859-1 /home/user/data/raw_b.txt > /home/user/data/sensor_b.csv

    cat << 'EOF' > /home/user/data/raw_a.txt
S01,2023-10-01T12:00:00Z,23.5
S02,2023-10-01T12:05:00Z,24.1
S01,BAD_DATE_FORMAT,25.0
S03,2023-10-01T12:10:00Z,22.1
S08,2023-10-01T11:55:00Z,21.0
EOF
    iconv -f UTF-8 -t UTF-16LE /home/user/data/raw_a.txt > /home/user/data/sensor_a.csv

    rm /home/user/data/raw_a.txt /home/user/data/raw_b.txt

    chmod -R 777 /home/user
