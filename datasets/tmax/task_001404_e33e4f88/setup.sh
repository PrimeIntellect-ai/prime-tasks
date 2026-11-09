#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc haproxy curl tzdata
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/pings.log
[2023-10-25T10:00:00Z] 192.168.1.10 SUCCESS latency=45ms
[2023-10-25T10:00:01Z] 192.168.1.11 SUCCESS latency=155ms
[2023-10-25T10:00:02Z] 192.168.1.12 SUCCESS latency=200ms
[2023-10-25T10:00:03Z] 192.168.1.11 SUCCESS latency=160ms
[2023-10-25T10:00:04Z] 10.0.0.5 SUCCESS latency=150ms
[2023-10-25T10:00:05Z] 192.168.1.15 SUCCESS latency=300ms
[2023-10-25T10:00:06Z] 10.0.0.5 SUCCESS latency=140ms
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
