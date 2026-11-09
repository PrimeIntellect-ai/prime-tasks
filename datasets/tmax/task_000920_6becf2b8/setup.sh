#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak cron sqlite3
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/field_notes.wav "The server passphrase is crimson sky. The calibration multiplier is two point zero."

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,reading
1,10.0
2,
3,30.0
4,40.0
5,
6,60.0
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
