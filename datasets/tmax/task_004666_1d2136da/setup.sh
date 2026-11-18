#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp_ms,sensor_id,temperature,humidity
1600000000000,A,20.0,50.0
1600000300000,A,22.0,52.0
1600000600000,A,,54.0
1600000900000,A,26.0,56.0
1600001200000,A,105.0,60.0
1600001500000,A,28.0,58.0
1600000000000,B,10.0,40.0
1600000500000,B,-60.0,42.0
1600000800000,B,14.0,44.0
1600001000000,B,16.0,
1600001600000,B,18.0,48.0
EOF

    chmod -R 777 /home/user
