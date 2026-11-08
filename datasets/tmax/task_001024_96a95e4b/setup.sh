#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensor_data.csv
time_min,temperature,humidity
0,20.0,50.0
2,22.0,52.0
5,25.0,55.0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
