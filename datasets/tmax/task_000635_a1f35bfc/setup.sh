#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
Error: Disk full on /dev/sda1
error disk full on dev sda1
Warning: disk almost full on /dev/sda1
System boot sequence initiated.
system boot sequence completed.
EOF

    chmod -R 777 /home/user
