#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor.csv
timestamp,sensor_id,reading_1,reading_2
2023-10-01T00:00:00,1,10.0,12.0
2023-10-01T01:00:00,1,11.5,12.6
2023-10-01T00:00:00,2,8.0,8.5
2023-10-01T01:00:00,2,8.2,8.1
2023-10-01T00:00:00,3,5.0,10.0
2023-10-01T01:00:00,3,5.0,10.0
2023-10-01T00:00:00,4,20.0,15.0
2023-10-01T01:00:00,4,18.0,15.0
EOF

    cat << 'EOF' > /home/user/target.csv
sensor_id,target_value
1,1.5
2,0.2
3,5.0
4,3.8
EOF

    chmod -R 777 /home/user
