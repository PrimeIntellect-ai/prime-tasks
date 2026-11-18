#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/fw_logs.txt
[2023-10-10 10:00:00] INFO: Connection accepted IP:10.0.0.5 PORT:22 - Allowed
[2023-10-10 10:05:00] ERROR: Port forwarding failed IP:192.168.1.100 PORT:8080 - Rule blocked
[2023-10-10 10:06:00] ERROR: Port forwarding failed IP:10.0.0.7 PORT:8080 - Rule blocked
[2023-10-10 10:07:00] WARNING: High latency IP:192.168.1.100 PORT:8080 - Congestion
[2023-10-10 10:08:00] ERROR: Port forwarding failed IP:172.16.0.5 PORT:9090 - Rule blocked
[2023-10-10 10:09:00] ERROR: Port forwarding failed IP:192.168.1.100 PORT:8080 - Rule blocked
[2023-10-10 10:10:00] ERROR: Port forwarding failed IP:10.1.1.1 PORT:8080 - Timeout
EOF

    chmod 644 /home/user/fw_logs.txt
    chmod -R 777 /home/user
