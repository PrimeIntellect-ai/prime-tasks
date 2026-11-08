#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
temp,pressure,humidity,vibration
10.0,101.2,45.0,0.5
12.0,101.5,41.0,0.6
14.0,101.1,37.0,0.5
16.0,100.9,,0.4
18.0,100.8,29.0,0.5
20.0,100.5,25.0,0.6
EOF

    chmod -R 777 /home/user
