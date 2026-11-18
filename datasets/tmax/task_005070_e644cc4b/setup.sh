#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_metrics.csv
timestamp,ip_address,metric_name,metric_value
2023-10-01T10:00:00,192.168.1.10,cpu_usage,10.0
2023-10-01T10:00:00,192.168.1.10,mem_usage,512.0
2023-10-01T10:05:00,192.168.1.10,cpu_usage,12.0
2023-10-01T10:05:00,192.168.1.10,cpu_usage,11.5
2023-10-01T10:10:00,192.168.1.10,cpu_usage,11.0
2023-10-01T10:15:00,192.168.1.10,cpu_usage,40.0
2023-10-01T10:00:00,10.0.0.5,cpu_usage,20.0
2023-10-01T10:05:00,10.0.0.5,mem_usage,1024.0
2023-10-01T10:10:00,10.0.0.5,cpu_usage,20.0
2023-10-01T10:15:00,10.0.0.5,cpu_usage,50.0
EOF

    chmod -R 777 /home/user
