#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/metrics.csv
Timestamp,CPU_Load,Memory_Usage
2023-10-25T10:00,45.2,1024
2023-10-25T10:01,46.1,1024
2023-10-25T10:02,44.8,1025
2023-10-25T10:03,50.2,1030
2023-10-25T10:04,49.9,1030
2023-10-25T10:05,52.1,1040
2023-10-25T10:06,60.5,1080
2023-10-25T10:07,85.5,1200
2023-10-25T10:08,45.0,1024
2023-10-25T10:09,44.5,1024
EOF

    cat << 'EOF' > /home/user/events.jsonl
{"Timestamp": "2023-10-25T10:00", "EventType": "INFO", "Message": "User logged in"}
{"Timestamp": "2023-10-25T10:01", "EventType": "INFO", "Message": "Page loaded \u2713"}
{"Timestamp": "2023-10-25T10:02", "EventType": "ERROR", "Message": "Broken unicode \u002"}
{"Timestamp": "2023-10-25T10:04", "EventType": "INFO", "Message": "Process \u12G started"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node A \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node B \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node C \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node D \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node E \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "ERROR", "Message": "Timeout on node F \u00"}
{"Timestamp": "2023-10-25T10:07", "EventType": "INFO", "Message": "Retry triggered"}
{"Timestamp": "2023-10-25T10:08", "EventType": "INFO", "Message": "System recovered"}
EOF

    chmod -R 777 /home/user
