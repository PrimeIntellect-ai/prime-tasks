#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
1696118400 SERVER_A cpu:45.2 mem:80.1 disk:50.0
2023-10-01T00:05:00Z SERVER_B cpu:95.0 mem:92.5 disk:88.0
1696118700 SERVER_A cpu:91.0 mem:91.0 disk:55.0
2023-10-01T00:10:00Z SERVER_C cpu:90.0 mem:90.1 disk:10.0
1696119000 SERVER_B cpu:90.1 mem:90.1 disk:88.0
EOF

    chmod 644 /home/user/raw_logs.txt
    chmod -R 777 /home/user
