#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,value,status_msg
2023-10-01 10:00:00,45.2,All good
2023-10-01 11:00:00,46.1,System normal
2023-10-01 13:00:00,88.5,Alerta ⚠️ 高温
2023-10-01 15:00:00,47.0,OK
2023-10-01 16:00:00,92.0,Fehler detected 🚨
2023-10-01 17:00:00,44.5,正常
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
