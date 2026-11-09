#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,temperature
1600002000,A,20.0
1600002100,A,21.0
1600002150,A,19.0
1600002300,A,22.0
1600002900,A,25.0
1600002300,B,15.0
1600002600,B,16.5
1600002650,B,16.0
1600002900,B,17.0
EOF

    chmod -R 777 /home/user
