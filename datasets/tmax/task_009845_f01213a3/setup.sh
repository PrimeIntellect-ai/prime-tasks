#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_logs.txt
[2023-10-01T12:00:00] IP=10.0.0.5 USER=guest TOKEN=2537273136 STATUS=SUCCESS
[2023-10-01T12:02:00] IP=192.168.1.100 USER=admin TOKEN=23262f2b2c STATUS=SUCCESS
[2023-10-01T12:05:00] IP=10.0.0.6 USER=admin TOKEN=1111111111 STATUS=FAILED
[2023-10-01T12:10:00] IP=172.16.0.4 USER=admin TOKEN=23262f2b2c STATUS=SUCCESS
[2023-10-01T12:15:00] IP=192.168.1.100 USER=admin TOKEN=23262f2b2c STATUS=SUCCESS
[2023-10-01T12:20:00] IP=8.8.8.8 USER=admin TOKEN=23262f2b2c STATUS=FAILED
[2023-10-01T12:25:00] IP=10.10.10.10 USER=admin TOKEN=abcdef1234 STATUS=SUCCESS
EOF

    chmod -R 777 /home/user
