#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_events.jsonl
{"timestamp": "2023-10-25T14:32:01Z", "service": "web", "action": "update", "details": "increased timeout"}
{"timestamp": "2023-10-25T14:45:00Z", "service": "web", "action": "restart", "details": "manual trigger"}
{"timestamp": "2023-10-25T14:50:00Z", "service": "api", "action": "update", "details": "corrupted unicode \u12X4 error"}
{"timestamp": "2023-10-25T15:05:00Z", "service": "db", "action": "backup", "details": "daily snapshot"}
{"timestamp": "2023-10-25T15:15:00Z", "service": "web", "action": "update", "details": "feature flag toggle"}
{"timestamp": "2023-10-25T15:42:00Z", "service": "api", "action": "restart", "details": "bad escape \uZZZZ crash"}
{"timestamp": "2023-10-26T09:12:00Z", "service": "db", "action": "update", "details": "index rebuild"}
EOF

    chmod -R 777 /home/user
