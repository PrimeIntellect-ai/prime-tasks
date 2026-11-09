#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,vibration,temperature
1001,10.0,20.0
1002,15.0,20.1
1002,15.0,20.1
1003,10.0,20.2
1004,15.0,20.3
1005,30.0,21.0
1005,30.0,21.0
1006,10.0,20.0
EOF

    chmod -R 777 /home/user
