#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/server.log
[2023-10-01 10:00:00] IP: 192.168.1.1 STATUS: 200
[2023-10-01 10:00:01] IP: 192.168.1.2 STATUS: 500
[2023-10-01 10:00:02] IP: 192.168.1.1 STATUS: 404
[2023-10-01 10:00:03] IP: 192.168.1.3 STATUS: 500
[2023-10-01 10:00:04] IP: 192.168.1.4 STATUS: 500
[2023-10-01 10:00:05] IP: 192.168.1.2 STATUS: 404
EOF

    cat << 'EOF' > /home/user/logs/app.log
[2023-10-01 10:00:00] USER: alice IP: 192.168.1.1 ACTION: login
[2023-10-01 10:00:01] USER: bob IP: 192.168.1.2 ACTION: crash
[2023-10-01 10:00:02] USER: alice IP: 192.168.1.1 ACTION: not_found
[2023-10-01 10:00:03] USER: charlie IP: 192.168.1.3 ACTION: crash
[2023-10-01 10:00:04] USER: dave IP: 192.168.1.4 ACTION: crash
[2023-10-01 10:00:05] USER: bob IP: 192.168.1.2 ACTION: not_found
[2023-10-01 10:00:06] USER: eve IP: 192.168.1.5 ACTION: logout
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
