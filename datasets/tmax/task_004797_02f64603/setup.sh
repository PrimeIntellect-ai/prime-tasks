#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature,humidity
2023-01-01T00:00:00Z,S1,20.0,40.0
2023-01-01T00:01:00Z,S1,22.0,45.0
2023-01-01T00:02:00Z,S1,24.0,50.0
2023-01-01T00:03:00Z,S1,-30.0,40.0
2023-01-01T00:04:00Z,S1,26.0,80.0
2023-01-01T00:05:00Z,S1,25.0,105.0
2023-01-01T00:06:00Z,S1,28.0,50.0
2023-01-01T00:00:00Z,S2,10.0,90.0
2023-01-01T00:01:00Z,S2,12.0,95.0
2023-01-01T00:02:00Z,S2,14.0,100.0
2023-01-01T00:03:00Z,S2,16.0,85.0
EOF

    chmod -R 777 /home/user
