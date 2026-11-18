#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/service_a.jsonl
{"timestamp": "2023-10-25T14:30:07Z", "service": "auth-service", "key": "memory_limit", "value": 512}
{"timestamp": "2023-10-25T14:30:09Z", "service": "auth-service", "key": "cpu_cores", "value": 3}
{"timestamp": "2023-10-25T14:30:15Z", "service": "auth-service", "key": "maintenance_mode", "value": true}
{"timestamp": "2023-10-25T14:30:22Z", "service": "auth-service", "key": "memory_limit", "value": 4096}
{"timestamp": "2023-10-25T14:30:45Z", "service": "payment-service", "key": "cpu_cores", "value": 4}
EOF

    cat << 'EOF' > /home/user/data/service_b.jsonl
{"timestamp": "2023-10-25T14:30:05Z", "service": "web-ui", "key": "memory_limit", "value": 1024}
{"timestamp": "2023-10-25T14:30:12Z", "service": "web-ui", "key": "maintenance_mode", "value": "false"}
{"timestamp": "2023-10-25T14:30:49Z", "service": "web-ui", "key": "cpu_cores", "value": 2}
{"timestamp": "2023-10-25T14:30:52Z", "service": "web-ui", "key": "unknown_key", "value": "test"}
EOF

    chmod -R 777 /home/user
