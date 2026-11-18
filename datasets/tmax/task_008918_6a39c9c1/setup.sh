#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev iptables coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic.log
[2023-10-25 10:00:01] [10.0.0.5] [192.168.1.50] USER:john SSN:123456789
[2023-10-25 10:00:02] [192.168.1.100] [10.0.0.5] 1968607A6B6A74637462746D
[2023-10-25 10:00:03] [10.0.0.6] [192.168.1.51] USER:alice SSN:987654321
EOF

    chmod -R 777 /home/user
