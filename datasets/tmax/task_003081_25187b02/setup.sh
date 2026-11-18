#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,reading,error_code
2023-10-01T10:00:00Z,alpha,150.5,
2023-10-01T10:01:00Z,alpha,-50.0,
2023-10-01T10:02:00Z,beta,200.0,
2023-10-01T10:03:00Z,alpha,100.5,E01
2023-10-01T10:04:00Z,gamma,500.0,
2023-10-01T10:05:00Z,beta,1001.0,
2023-10-01T10:06:00Z,alpha,49.5,
EOF

    chmod -R 777 /home/user
