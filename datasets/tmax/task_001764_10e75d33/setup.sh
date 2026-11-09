#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,timestamp,metric_A,metric_B,event_log
S001,1710000100,10.5,50.1,Error;Timeout;Code99
S002,1710000105,15.2,48.0,BootSeq;OK
S003,1710000110,14.8,47.5,HEARTBEAT
S001,1710000100,99.9,99.9,Dupe;Data
S002,1710000105,-1.0,-1.0,IGNORE
S004,1710000115,22.1,30.0,Warn_Temp;High
S001,1710000120,11.0,49.5,REBOOT;Manual
EOF

    chmod -R 777 /home/user
