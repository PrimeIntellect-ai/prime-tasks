#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
ID,Timestamp,Temperature,Humidity
1,2023-10-01T00:00:00Z,22.5,45.0
1,2023-10-01T01:00:00Z,,45.5
1,2023-10-01T02:00:00Z,100.0,46.0
2,2023-10-01T00:00:00Z,23.0,40.0
2,2023-10-01T01:00:00Z,23.5,
3,2023-10-01T00:00:00Z,21.0,50.0
4,2023-10-01T00:00:00Z,-15.0,30.0
EOF

    cat << 'EOF' > /home/user/sensor_metadata.csv
ID,Location,Model
1,Lab1,X100
2,Lab2,Y200
3,Lab1,X100
4,Lab3,Z300
EOF

    chmod -R 777 /home/user
