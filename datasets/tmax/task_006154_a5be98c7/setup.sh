#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/raw_data/sensor.csv
timestamp,temperature_celsius
2023-10-01 10:00:15,45.5
2023-10-01 10:00:45,46.5
2023-10-01 10:01:30,47.0
2023-10-01 10:05:10,50.0
2023-10-01 10:06:05,51.0
2023-10-01 10:07:55,52.0
EOF

    cat << 'EOF' > /home/user/raw_data/state.csv
timestamp,machine_state
2023-10-01 09:59:00,ON
2023-10-01 10:02:30,ERROR
2023-10-01 10:05:00,OFF
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
