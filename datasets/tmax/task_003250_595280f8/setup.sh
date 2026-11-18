#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature,humidity
2023-01-01T00:00:00Z,1,20.5,45.0
2023-01-01T01:00:00Z,2,21.0,50.0
2023-01-01T02:00:00Z,11,25.0,55.0
2023-01-01T03:00:00Z,3,-60.0,40.0
2023-01-01T04:00:00Z,4,22.0,110.0
2023-01-01T05:00:00Z,5,19.5,42.0
2023-01-01T06:00:00Z,1,bad,42.0
2023-01-01T07:00:00Z,6,23.0,48.0
2023-01-01T08:00:00Z,7,21.5,49.0
2023-01-01T09:00:00Z,8,20.0,47.0
EOF

    chmod -R 777 /home/user
