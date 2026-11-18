#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_logs.txt
[DEBUG] Sensor-A1 reported at Jan 05 2024 14:30:00. Loc: (12, -5). All good.
[INFO] Sensor-B2 pinged on 2024/01/05 2:35 PM. Loc: (-10, 20). Battery low.
[ERROR] Sensor-C3 failed at 14:40 01-05-2024. Loc: (invalid, 9).
[INFO] Sensor-D4 active at 2024-01-05 14:45:00. Loc: (0, 0).
Corrupted line without proper info.
[WARN] Sensor-E5 offline at Jan 05 2024 10:15:00. Loc: (7, 8).
[INFO] Sensor-F6 at 2024-01-05 16:00:00. No location data.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
