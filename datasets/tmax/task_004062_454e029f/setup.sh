#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,temperature,comments
2023-10-01T10:01:00,S1,20.00,Start
2023-10-01T10:05:00,S1,,Missing temp
2023-10-01T10:15:00,S1,22.00,Normal
2023-10-01T10:20:00,S1,24.00,"Embedded
newline here"
2023-10-01T10:30:00,S1,,Missing temp again
2023-10-01T11:05:00,S1,26.00,Normal
2023-10-01T11:20:00,S1,28.00,Normal
2023-10-01T11:45:00,S1,,Missing
2023-10-01T12:10:00,S1,30.00,"Another
Bad
Line"
2023-10-01T12:20:00,S1,20.00,Cooling down
EOF

    chmod -R 777 /home/user
