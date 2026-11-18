#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl_pipeline/raw

    cat << 'EOF' > /home/user/etl_pipeline/raw/raw_data1.csv
2023-10-01T10:00:00,SENSOR_A,USER_123,22.5
2023-10-01T10:01:00,SENSOR_B,USER_456,23.1
2023-10-01T10:02:00,SENSOR_A,USER_123,22.7
EOF

    cat << 'EOF' > /home/user/etl_pipeline/raw/raw_data2.csv
2023-10-01T10:03:00,SENSOR_C,USER_789,19.8
2023-10-01T10:04:00,SENSOR_A,USER_001,21.0
EOF

    cat << 'EOF' > /home/user/etl_pipeline/raw/raw_data3.csv
2023-10-01T10:05:00,SENSOR_B,USER_456,23.5
2023-10-01T10:06:00,SENSOR_C,USER_999,19.2
EOF

    chown -R user:user /home/user/etl_pipeline
    chmod -R 777 /home/user
