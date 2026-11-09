#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,cpu_percent,memory_usage,incident_log
2023-10-15T08:00:15Z,40.0,1GB,Started
2023-10-15T08:01:45Z,50.0,1024MB,"Spike
Line2"
2023-10-15T08:02:10Z,60.0,1.5GB,Normal
2023-10-15T08:03:05Z,70.0,2048000KB,"Error
Details"
2023-10-15T08:05:59Z,80.0,2GB,OK
EOF

    chmod -R 777 /home/user
