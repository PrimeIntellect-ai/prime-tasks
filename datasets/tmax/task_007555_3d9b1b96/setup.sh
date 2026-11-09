#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp_ms,sensor_id,temperature
1000,SENS-01,20.0
1500,SENS-02,22.1
2000,SENS-42,15.5
2500,SENS-01,19.8
3000,SENS-42,16.0
3500,SENS-03,25.0
4000,SENS-42,16.5
4500,SENS-02,22.4
5000,SENS-42,17.0
6000,SENS-42,17.5
EOF

    chmod -R 777 /home/user
