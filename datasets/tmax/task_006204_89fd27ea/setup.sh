#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_metrics.csv
timestamp,server_id,cpu_usage
2023-10-01 10:00:15,PROD-A,50.0
2023-10-01 10:00:45,PROD-A,60.0
2023-10-01 10:05:10,PROD-A,80.0
2023-10-01 10:00:00,DEV-A,99.9
2023-10-01 10:01:00,DEV-A,99.9
2023-10-01 10:58:00,PROD-B,10.0
2023-10-01 11:02:00,PROD-B,30.0
2023-10-01 11:05:00,PROD-B,45.0
EOF

    chmod -R 777 /home/user
