#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.csv
Timestamp,Status,Temp,Humidity
2023-11-01T14:22:10Z,All%20Good,23.4,50.1
2023-11-01T14:59:59Z,Sensor%20Drift%3F,24.0,51.2
2023-11-01T15:00:05Z,WARN%3A%20High%20Temp,28.5,48.0
2023-11-01T16:15:30Z,RECALIBRATING%2E%2E%2E,22.1,55.5
EOF

    cat << 'EOF' > /home/user/expected_data.csv
timestamp_aligned,metric_name,metric_value,status_normalized
2023-11-01T14:00:00Z,Temp,23.4,all_good
2023-11-01T14:00:00Z,Humidity,50.1,all_good
2023-11-01T14:00:00Z,Temp,24.0,sensor_drift?
2023-11-01T14:00:00Z,Humidity,51.2,sensor_drift?
2023-11-01T15:00:00Z,Temp,28.5,warn:_high_temp
2023-11-01T15:00:00Z,Humidity,48.0,warn:_high_temp
2023-11-01T16:00:00Z,Temp,22.1,recalibrating...
2023-11-01T16:00:00Z,Humidity,55.5,recalibrating...
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
