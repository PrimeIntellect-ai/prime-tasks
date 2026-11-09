#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg sqlite3
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/raw_sensors.csv
timestamp,sensor_id,value,event_remarks
2023-10-01 10:00:00,S1,10.0,"Start
recording"
2023-10-01 11:00:00,S2,25.0,"Normal"
2023-10-01 12:00:00,S1,13.0,"Spike
detected"
2023-10-01 13:00:00,S2,28.0,"Normal"
2023-10-01 14:00:00,S1,12.0,"End"
EOF

    espeak -w /app/calibration.wav "Sensor S1 offset is plus five. Sensor S2 offset is minus three."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
