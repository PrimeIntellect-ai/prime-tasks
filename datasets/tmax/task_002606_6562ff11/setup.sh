#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /opt/data
    cat << 'EOF' > /opt/data/server_logs.txt
[2023-10-01 09:59:00] INFO - alpha - T:30.0 L:0.5
[2023-10-01 10:00:00] INFO - omega - T:44.0 L:1.2
[2023-10-01 10:00:30] ERROR - beta - T:90.0 L:4.0
[2023-10-01 10:01:00] WARN - omega - T:MISSING L:1.3
[2023-10-01 10:02:00] WARN - omega - T:MISSING L:1.4
[2023-10-01 10:03:00] INFO - omega - T:50.0 L:1.5
[2023-10-01 10:03:15] INFO - alpha - T:31.0 L:0.6
[2023-10-01 10:04:00] INFO - omega - T:MISSING L:1.45
[2023-10-01 10:05:00] INFO - omega - T:MISSING L:1.5
[2023-10-01 10:06:00] INFO - omega - T:MISSING L:1.6
[2023-10-01 10:07:00] INFO - omega - T:56.0 L:1.7
[2023-10-01 10:08:00] INFO - alpha - T:32.0 L:0.7
EOF
    chmod 644 /opt/data/server_logs.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
