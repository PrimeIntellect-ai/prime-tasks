#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,sensor_id,temperature,humidity
1000,S1,20.0,45.0
1001,S2,22.0,50.0
1002,S1,-60.0,40.0
1003,S3,21.0,105.0
1004,S1,24.0,45.0
1005,S2,23.0,55.0
1006,S3,-55.0,110.0
1007,S1,26.0,45.0
1008,S2,20.0,50.0
1009,S1,20.0,45.0
EOF

    chmod -R 777 /home/user
