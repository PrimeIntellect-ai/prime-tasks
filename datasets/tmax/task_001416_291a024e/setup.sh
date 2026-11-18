#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_events.json
[
  {"id": 1, "email": "alice@example.com", "ip_address": "192.168.1.5", "event_type": "view", "value": 12},
  {"id": 2, "email": "bob@domain.org", "ip_address": "10.1.2.3", "event_type": "buy", "value": 85},
  {"id": 3, "email": "charlie@test.net", "ip_address": "172.16.0.4", "event_type": "click", "value": 50}
]
EOF

    chmod -R 777 /home/user
