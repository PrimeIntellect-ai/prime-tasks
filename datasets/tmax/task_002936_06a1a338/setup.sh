#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl_pipeline

    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,ip_address,message
2023-10-15 14:05:01,192.168.1.10,"User logged in successfully"
2023-10-15 14:12:33,10.0.0.5,"ERROR: Connection timeout"
2023-10-15 14:15:00,192.168.1.11,"Payload received:
embedded newline here"
2023-10-15 14:45:12,192.168.1.12,"Standard info log"
2023-10-15 15:02:11,10.0.0.5,"ERROR: Disk space low"
2023-10-15 15:30:00,192.168.1.15,"Traceback (most recent call last):
  File 'main.py', line 1
    import sys"
2023-10-15 15:45:00,192.168.1.10,"Job completed"
EOF

    chmod -R 777 /home/user
