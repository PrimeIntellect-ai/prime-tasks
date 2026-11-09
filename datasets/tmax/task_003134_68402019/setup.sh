#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs
    cat << 'EOF' > /home/user/raw_logs/app1.log
INFO 2023-10-01 Starting service
DEBUG USER=alice PASSWORD=wonderland IP=192.168.1.5
INFO User logged in
ERROR USER=bob PASSWORD=builder Connection failed
EOF

    cat << 'EOF' > /home/user/raw_logs/app2.log
INFO 2023-10-02 Service running normally
DEBUG USER=admin PASSWORD=admin
INFO USER=charlie PASSWORD=chocolate_factory IP=10.0.0.2
EOF

    chown -R user:user /home/user/raw_logs
    chmod -R 777 /home/user
