#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
timestamp,sensor_id,value
2023-10-01T10:00:00,A,10.0
2023-10-01T10:01:00,A,
2023-10-01T10:02:00,A,14.0
2023-10-01T10:02:00,A,14.0
2023-10-01T10:03:00,A,16.0
2023-10-01T10:04:00,A,
2023-10-01T10:04:00,A,
2023-10-01T10:06:00,A,22.0
2023-10-01T09:59:00,A,8.0
EOF

    chmod -R 777 /home/user
