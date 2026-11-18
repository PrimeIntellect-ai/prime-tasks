#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_metrics.csv
timestamp,cpu_usage,mem_usage,disk_io,temp
2023-01-01T00:00:00,45.5,1024.0,150,42.1
2023-01-01T00:01:00,10.0,bad_data,20,35.0
2023-01-01T00:02:00,0.0,500.0,10,41.0
2023-01-01T00:03:00,80.0,2048.0,500,65.5
2023-01-01T00:04:00,50.0,1000.0
2023-01-01T00:05:00,20.0,800.0,100,39.0
2023-01-01T00:06:00,100.0,4000.0,1000,85.2
2023-01-01T00:07:00,50.0,-100.0,100,45.0
2023-01-01T00:08:00,25.0,2000.0,150,40.0
2023-01-01T00:09:00,25.0,2000.0,150,40.1
EOF

    chmod -R 777 /home/user
