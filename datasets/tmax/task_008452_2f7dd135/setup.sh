#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_experiment.csv
timestamp,sensor_1,sensor_2,error_code
1620000001,120.5,-10.2,0
1620000002,180.0,-60.5,1
1620000003,NaN,15.0,0
1620000004,,NaN,0
1620000005,100.0,20.0,0,extra_column
bad_timestamp,10.0,10.0,0
1620000006,140.0,0.0,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
