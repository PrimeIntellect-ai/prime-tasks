#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas jinja2

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/metrics.csv
timestamp,server_id,cpu_usage,mem_usage
2023-10-10T05:00:00Z,srv-1,45.0,60.0
2023-10-10T05:05:00Z,srv-1,46.0,61.0
2023-10-10T05:10:00Z,srv-1,45.5,60.5
2023-10-10T05:15:00Z,srv-1,88.0,80.0
2023-10-10T05:20:00Z,srv-1,40.0,50.0
2023-10-10T08:00:00Z,srv-2,50.0,70.0
2023-10-10T08:05:00Z,srv-2,52.0,71.0
2023-10-10T08:10:00Z,srv-2,51.0,70.5
2023-10-10T08:15:00Z,srv-2,95.0,90.0
2023-10-10T13:00:00Z,srv-1,30.0,40.0
2023-10-10T13:05:00Z,srv-1,31.0,41.0
2023-10-10T13:10:00Z,srv-1,85.0,75.0
EOF

    chmod -R 777 /home/user
