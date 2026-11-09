#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/reports

    cat << 'EOF' > /home/user/generate_csv.py
import sys

data = [
    b'2023-10-01T08:00:00Z,charlie@domain.com,"Standard feedback, all good!"\n',
    b'2023-10-15T14:30:00Z,alice@example.com,"This has an\nembedded newline."\n',
    b'2023-11-05T09:15:00Z,bob@test.org,"Invalid chars \xff\xfe here."\n',
    b'2023-11-20T11:00:00Z,david@company.net,"Multiple\nnewlines\n\xe2\x82\xac"\n'
]

with open('/home/user/feedback.csv', 'wb') as f:
    for line in data:
        f.write(line)
EOF

    python3 /home/user/generate_csv.py
    rm /home/user/generate_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
