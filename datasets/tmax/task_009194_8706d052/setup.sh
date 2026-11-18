#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.csv
timestamp,server_id,cpu_pct,ram_mb,event_details
2023-10-12 10:00:00,srv-1,45.5,2048,Normal operation
2023-10-12T10:01:00Z,srv-2,99.9,4096,"High load detected
Investigate immediately"
2023-10-12 10:02:00,srv-1,105.0,2048,Invalid CPU spike
2023-10-12T10:03:00Z,srv-3,12.0,-500,Invalid RAM allocation
2023-10-12 10:04:00,srv-1,22.1,8192,"Routine backup started
Lines: 400
Status: OK"
2023-10-12T10:05:00Z,srv-2,50.0,4096,Normal operation
2023-10-12 10:06:00,srv-3,NaN,1024,Broken float
2023-10-12 10:07:00,srv-1,10.0,2048,Idle
2023-10-12 10:08:00,srv-2,15.5,4096,Idle
2023-10-12 10:09:00,srv-3,18.0,1024,Idle
EOF

    chmod -R 777 /home/user
