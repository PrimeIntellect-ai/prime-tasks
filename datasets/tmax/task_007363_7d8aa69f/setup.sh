#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,temperature,humidity
1000000000,S1,20.00,50.00
1000000060,S1,,52.00
1000000120,S1,22.00,
1000000240,S1,24.00,58.00
1000000000,S2,10.00,80.00
1000000180,S2,16.00,86.00
1000000240,S2,18.00,88.00
EOF

    chmod -R 777 /home/user
