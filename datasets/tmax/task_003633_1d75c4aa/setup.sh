#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/incoming
    mkdir -p /home/user/data/output
    mkdir -p /home/user/data/archive

    cat << 'EOF' > /home/user/data/incoming/batch1.csv
event_id,timestamp,device_id,sensor_value
e1,2023-10-01T10:00:00Z,devA,10.0
e2,2023-10-01T10:01:00Z,devB,20.0
e3,2023-10-01T10:02:00Z,devA,15.0
EOF

    cat << 'EOF' > /home/user/data/incoming/batch2.csv
event_id,timestamp,device_id,sensor_value
e2,2023-10-01T10:01:00Z,devB,20.0
e4,2023-10-01T10:03:00Z,devA,20.0
e5,2023-10-01T10:04:00Z,devA,25.0
e6,2023-10-01T10:05:00Z,devB,30.0
e7,2023-10-01T10:06:00Z,devB,40.0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
