#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
id,timestamp,sensor_id,value,description
1,2023-10-12T14:35:59,TEMP_A,25.5,"Normal operation"
2,2023-10-12T14:36:15,TEMP_B,12.0,"Fan starting"
3,2023-10-12T14:37:05,TEMP_A,28.0,"Spike detected
Requires
investigation"
4,2023-10-12T14:37:45,PRESS_A,101.3,"Pressure stable"
5,2023-10-12T14:38:12,TEMP_A,155.0,"Anomalous high value,
clamping expected."
6,2023-10-12T14:39:59,TEMP_A,-60.0,"Anomalous low value,
clamping expected."
EOF

    chmod 644 /home/user/raw_sensors.csv
    chmod -R 777 /home/user
