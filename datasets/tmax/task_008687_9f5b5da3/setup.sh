#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,value
10,S1,50.0
10,S1,60.0
11,S1,55.0
12,S1,58.0
13,S1,61.0
14,S1,40.0
10,S2,20.0
11,S2,22.0
11,S2,24.0
12,S2,25.0
EOF

    chmod -R 777 /home/user
