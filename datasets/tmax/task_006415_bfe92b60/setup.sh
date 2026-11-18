#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/raw.log
2023-10-25T14:30:05Z | 192.168.1.1 | User logged in successfully
2023-10-25T14:30:00Z | 10.0.0.1 | Health check ping!
2023-10-25T14:30:06Z | 192.168.1.2 | User logged in successfully! (mobile)
2023-10-25T14:30:15Z | 10.0.0.2 | Error: Database connection failed.
2023-10-25T14:30:20Z | 192.168.1.5 | Requesting data payload #1234
2023-10-25T14:30:21Z | 192.168.1.6 | requesting DATA payload #1234!!
2023-10-25T14:30:35Z | 10.0.0.3 | Normal background sync
EOF

    chmod -R 777 /home/user
