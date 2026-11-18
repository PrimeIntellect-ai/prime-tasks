#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deployments/prod
    mkdir -p /home/user/deployments/dev
    mkdir -p /home/user/apps/app1
    mkdir -p /home/user/apps/app2
    mkdir -p /home/user/apps/app3
    mkdir -p /home/user/mock_metrics

    ln -s /home/user/deployments/prod /home/user/apps/app1/env
    ln -s /home/user/deployments/prod /home/user/apps/app2/env
    ln -s /home/user/deployments/dev /home/user/apps/app3/env

    cat << 'EOF' > /home/user/mock_metrics/1001.json
{"pid": 1001, "app": "app1", "memory_mb": 800, "cpu_percent": 60.5}
EOF

    cat << 'EOF' > /home/user/mock_metrics/1002.json
{"pid": 1002, "app": "app1", "memory_mb": 200, "cpu_percent": 15.0}
EOF

    cat << 'EOF' > /home/user/mock_metrics/1003.json
{"pid": 1003, "app": "app2", "memory_mb": 600, "cpu_percent": 40.0}
EOF

    cat << 'EOF' > /home/user/mock_metrics/1004.json
{"pid": 1004, "app": "app3", "memory_mb": 256, "cpu_percent": 10.0}
EOF

    chmod -R 777 /home/user
