#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import csv

input_file = '/home/user/raw_logs.csv'
expected_file = '/home/user/expected_stats.csv'

os.makedirs('/home/user', exist_ok=True)

data = [
    (300, 'u1', 'hello \\u1234 world'),
    (310, 'u2', 'test \\u12Z4 fail'),
    (320, 'u3', 'normal text here'),
    (330, 'u4', 'normal text here'),
    (340, 'u5', 'normal text here'),
    (350, 'u6', 'normal text here'),
    (360, 'u7', 'normal text here'),
    (370, 'u8', 'normal text here'),
    (380, 'u9', 'normal text here'),
    (390, 'u10', 'normal text here'),
    (605, 'u1', '0123456789'),
    (615, 'u2', '0123456789'),
    (625, 'u3', '0123456789'),
    (635, 'u4', '0123456789'),
    (645, 'u5', '0123456789'),
    (1250, 'u1', 'abc'),
    (1260, 'u1', 'def'),
]

with open(input_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp_sec', 'user_id', 'query_text'])
    for row in data:
        writer.writerow(row)

expected_csv = """bucket_start_ts,query_count,rolling_avg_length,status
300,10,16,FLAGGED
600,5,14,OK
1200,2,8,OK
"""

with open(expected_file, 'w') as f:
    f.write(expected_csv)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
