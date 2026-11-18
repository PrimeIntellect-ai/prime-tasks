#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/raw_a.csv
2023-10-01T08:15:00Z,10.0,A
2023-10-01T08:45:00Z,20.0,A
2023-10-01T08:45:00Z,20.0,A
2023-10-01T09:10:00Z,15.5,A
2023-10-01T10:05:00Z,100.0,A

EOF

    cat << 'EOF' > /tmp/raw_b.csv
2023-10-01T08:05:00Z,12.0,B
2023-10-01T08:55:00Z,14.0,B

2023-10-01T09:30:00Z,15.5,B
2023-10-01T09:30:00Z,15.5,B
2023-10-01T11:00:00Z,50.0,B
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/raw_a.csv > /home/user/data/sensor_a.csv
    iconv -f UTF-8 -t ISO-8859-1 /tmp/raw_b.csv > /home/user/data/sensor_b.csv

    rm /tmp/raw_a.csv /tmp/raw_b.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
