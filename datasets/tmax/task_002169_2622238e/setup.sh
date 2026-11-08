#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/file1.csv
timestamp,sensor_id,metric,value
2023-01-01 09:05:00,S1,temp,20.0
[DEBUG] Calibrating S1...
2023-01-01 09:45:00,S1,temp,21.0
2023-01-01 10:10:00,S2,temp,22.5
ERROR: Network lag detected
2023-01-01 10:15:00,S2,temp,23.5
2023-01-01 10:20:00,S1,temp,19.5
2023-01-01 10:55:00,S1,temp,19.5
EOF

    cat << 'EOF' > /home/user/raw_data/file2.csv
2023-01-01 10:30:00,S2,humidity,40.0
2023-01-01 11:05:00,S1,temp,24.0
2023-01-01 11:15:00,S1,temp,26.0
[INFO] Restarting sensor S3
2023-01-01 11:20:00,S3,temp,18.0
2023-01-01 11:59:59,S3,temp,18.5
EOF

    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
