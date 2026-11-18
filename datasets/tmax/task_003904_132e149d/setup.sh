#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,Sensor_East,Sensor_North,Sensor_South
2023-10-01T10:00,19.0 C,20.0 C,22.0 C
2023-10-01T10:05,19.2 C,20.5 C,ERR
2023-10-01T10:10,ERR,21.0 C,22.4 C
2023-10-01T10:15,19.6 C,ERR,22.6 C
2023-10-01T10:20,19.8 C,22.0 C,22.8 C
EOF

    chmod -R 777 /home/user
