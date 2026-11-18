#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/telemetry_data

    cat << 'EOF' > /home/user/telemetry_data/part_1.csv
user_id,timestamp,event_type,latency_ms,payload_size
1,2023-01-01T10:00:00Z,click,500,100
1,2023-01-01T10:05:00Z,scroll,1500,200
1,2023-01-01T10:10:00Z,click,-100,50
2,2023-01-01T10:15:00Z,view,1200,
EOF

    cat << 'EOF' > /home/user/telemetry_data/part_2.csv
user_id,timestamp,event_type,latency_ms,payload_size
2,2023-01-01T10:20:00Z,,800,300
3,2023-01-01T10:25:00Z,scroll,200,150
4,2023-01-01T10:30:00Z,click,1050,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
