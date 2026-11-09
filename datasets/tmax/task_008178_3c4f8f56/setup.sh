#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/temperature.csv
timestamp,device_id,temp_c
2023-10-01T10:00:00,D1,28.0
2023-10-01T10:01:00,D1,29.5
2023-10-01T10:02:00,D1,31.0
2023-10-01T10:03:00,D1,32.0
2023-10-01T10:04:00,D1,33.0
2023-10-01T10:00:00,D2,25.0
2023-10-01T10:01:00,D2,26.0
2023-10-01T10:02:00,D2,27.0
EOF

    cat << 'EOF' > /home/user/humidity.csv
timestamp,device_id,humidity_pct
2023-10-01T10:00:00,D1,65.0
2023-10-01T10:01:00,D1,72.0
2023-10-01T10:02:00,D1,75.0
2023-10-01T10:03:00,D1,71.0
2023-10-01T10:04:00,D1,60.0
2023-10-01T10:00:00,D2,80.0
2023-10-01T10:01:00,D2,85.0
2023-10-01T10:02:00,D2,75.0
EOF

    chmod -R 777 /home/user
