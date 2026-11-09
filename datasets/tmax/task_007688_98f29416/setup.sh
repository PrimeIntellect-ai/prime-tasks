#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/probe.log
2023-10-01T10:00:00 192.168.1.10 OK
2023-10-01T10:01:00 10.0.0.5 TIMEOUT
2023-10-01T10:02:00 172.16.0.2 DROP
2023-10-01T10:03:00 10.0.0.5 TIMEOUT
2023-10-01T10:04:00 192.168.1.20 OK
2023-10-01T10:05:00 10.10.10.10 DROP
2023-10-01T10:06:00 192.168.1.10 OK
EOF

    cat << 'EOF' > /home/user/net_users.conf
alice:admin,users
bob:users
charlie:dev,users
diana:netadmin,users
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
