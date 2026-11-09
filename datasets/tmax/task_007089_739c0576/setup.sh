#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_sensor.csv
2023-10-01T10:00:00Z,S1,20.0,50.0
2023-10-01T10:05:00Z,S2,22.0,40.0
2023-10-01T10:10:00Z,S1,21.0,
2023-10-01T10:05:00Z,S2,22.0,40.0
2023-10-01T10:15:00Z,S1,,48.0
2023-10-01T10:20:00Z,S1,23.0,45.0
2023-10-01T10:25:00Z,S2,21.5,42.0
2023-10-02T09:00:00Z,S1,19.0,55.0
2023-10-02T09:05:00Z,S2,20.0,
2023-10-02T09:10:00Z,S1,,52.0
2023-10-02T09:15:00Z,S2,21.0,44.0
2023-10-01T10:00:00Z,S1,99.9,99.9
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
