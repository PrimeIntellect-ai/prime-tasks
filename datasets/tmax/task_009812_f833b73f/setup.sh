#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/logs.jsonl
{"timestamp":"2023-11-01T08:15:30Z", "event_type":"api_call", "status_code":200}
{"timestamp":"2023-11-01T08:45:10Z", "event_type":"api_call", "status_code":500}
{"timestamp":"2023-11-01T08:50:00Z", "event_type":"login", "status_code":200}
{"timestamp":"2023-11-01T09:10:00Z", "event_type":"api_call", "status_code":200, "msg":"\u12G4"}
{"timestamp":"2023-11-01T09:15:00Z", "event_type":"api_call", "status_code":999}
{"timestamp":"2023-11-01T09:20:00Z", "event_type":"api_call", "status_code":201}
{"timestamp":"2023-11-01T09:25:00Z", "event_type":"api_call", "status_code":404}
{"timestamp":"2023-11-01T09:30:00Z", "event_type":"api_call", "status_code":403}
{"timestamp":"2023-11-01T10:05:00Z", "event_type":"api_call", "status_code":200}
{"timestamp":"2023-11-01T10:15:00Z", "event_type":"api_call", "status_code":502}
{"timestamp":"2023-11-01T10:20:00Z", "event_type":"api_call", "status_code":503}
{"timestamp":"2023-11-01T10:25:00Z", "event_type":"api_call", "status_code":200, "msg":"\uZZZZ"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
