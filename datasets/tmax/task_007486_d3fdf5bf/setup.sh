#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_logs.txt
[2023-10-01T12:00:01Z] DEBUG - system booting up, sensors initializing
[2023-10-01T12:00:02Z] INFO - sensor_id: S1, val: 10.5
[2023-10-01T12:00:03Z] INFO - sensor_id: S2, val: 100.0
[2023-10-01T12:00:04Z] INFO - sensor_id: S1, val: 11.0
[2023-10-01T12:00:04Z] WARN - battery low on S2
[2023-10-01T12:00:05Z] ERROR - sensor_id: S1, val: 45.0
[2023-10-01T12:00:06Z] INFO - sensor_id: S1, val: 46.0
[2023-10-01T12:00:07Z] INFO - sensor_id: S2, val: 101.0
[2023-10-01T12:00:08Z] INFO - sensor_id: S1, val: 20.0
EOF

    chmod -R 777 /home/user
