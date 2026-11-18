#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-12 10:00:00.123] INFO duration=100
[2023-10-12 10:00:00.456] INFO duration=200
[2023-10-12 10:00:01.001] ERROR something wrong
[2023-10-12 10:00:02.999] INFO duration=150
junk line
[2023-10-12 10:00:05.000] INFO duration=50
[2023-10-12 10:00:07.123] INFO duration=200
[2023-10-12 10:00:08.000] INFO duration=250
EOF

    chmod -R 777 /home/user
