#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk libc-bin
    pip3 install pytest

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/temp1.csv
timestamp,sensor_id,temperature
2023-10-01T00:00:00Z,sensor_1,20.0
2023-10-01T00:01:00Z,sensor_1,21.5
2023-10-01T00:02:00Z,sensor_1,38.0
2023-10-01T00:03:00Z,sensor_1,37.0
EOF

    cat << 'EOF' > /home/user/raw_data/temp2.csv
timestamp,sensor_id,temperature
2023-10-01T00:00:30Z,sensor_2,15.0
2023-10-01T00:01:30Z,sensor_2,14.0
2023-10-01T00:02:30Z,sensor_2,-5.0
2023-10-01T00:03:30Z,sensor_2,-4.0
EOF

    iconv -f UTF-8 -t UTF-16LE /home/user/raw_data/temp1.csv > /home/user/raw_data/sensor_1.csv
    iconv -f UTF-8 -t UTF-16LE /home/user/raw_data/temp2.csv > /home/user/raw_data/sensor_2.csv
    rm /home/user/raw_data/temp1.csv /home/user/raw_data/temp2.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
