#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_access.log
{"timestamp": "2023-10-25T14:32:05Z", "ip": "10.0.0.1", "status": 200, "bytes": 500}
{"timestamp": "2023-10-25T14:32:15Z", "ip": "10.0.0.2", "status": 200, "bytes": 1000}
{"timestamp": "2023-10-25T14:32:55Z", "ip": "10.0.0.1", "status": 200, "bytes": 200}
{"timestamp": "2023-10-25T14:33:01Z", "ip": "10.0.0.3", "status": 404, "bytes": 100}
{"timestamp": "2023-10-25T14:33:20Z", "ip": "10.0.0.3", "status": 200, "bytes": 400}
{"timestamp": "2023-10-25T14:33:59Z", "ip": "10.0.0.4", "status": 500, "bytes": 50}
{"timestamp": "2023-10-25T14:35:10Z", "ip": "10.0.0.1", "status": 200, "bytes": 800}
{"timestamp": "2023-10-25T14:35:12Z", "ip": "10.0.0.5", "status": 200, "bytes": 800}
EOF

    chmod -R 777 /home/user
