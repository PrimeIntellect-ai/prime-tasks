#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensors.csv
sensor_id,location,calibration_factor
1,loc1,1.2
2,loc2,0.8
3,loc3,bad_val
4,loc4,2.0
EOF

    cat << 'EOF' > /home/user/data/readings.csv
timestamp,sensor_id,raw_value,status
1000,1,10.0,OK
1001,2,5.0,WARN
1002,3,10.0,OK
1003,1,-5.0,OK
1004,4,0.0,ERR
1005,5,10.0,OK
1006,2,invalid,OK
EOF

    chmod -R 777 /home/user
