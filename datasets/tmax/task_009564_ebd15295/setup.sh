#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/monitor_config.json
{
    "global_timeout": 30,
    "endpoints": [
        {
            "name": "db_service",
            "url": "http://localhost:5432/ping"
        }
    ]
}
EOF

    chmod -R 777 /home/user
