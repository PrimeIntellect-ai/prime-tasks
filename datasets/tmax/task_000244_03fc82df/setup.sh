#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/remote_configs
    mkdir -p /home/user/local_configs

    cat << 'EOF' > /home/user/remote_configs/srv1_t1.json
{"server_id": "srv1", "timestamp": 1, "metrics": {"max_conn": 100.0, "timeout": 30.0}}
EOF

    cat << 'EOF' > /home/user/remote_configs/srv1_t2.json
{"server_id": "srv1", "timestamp": 2, "metrics": {"max_conn": 160.0, "timeout": 30.0}}
EOF

    cat << 'EOF' > /home/user/remote_configs/srv2_t1.json
{"server_id": "srv2", "timestamp": 1, "metrics": {"max_conn": 500.0, "timeout": 300.0}}
EOF

    cat << 'EOF' > /home/user/remote_configs/srv2_t2.json
{"server_id": "srv2", "timestamp": 2, "metrics": {"max_conn": 500.0, "timeout": 5.0}}
EOF

    cat << 'EOF' > /home/user/remote_configs/srv2_t3.json
{"server_id": "srv2", "timestamp": 3, "metrics": {"max_conn": 200.0, "timeout": 300.0}}
EOF

    cat << 'EOF' > /home/user/remote_configs/srv3_t1.json
{"server_id": "srv3", "timestamp": 1, "metrics": {"max_conn": -10.0, "timeout": 50.0}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
