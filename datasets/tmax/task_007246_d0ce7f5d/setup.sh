#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task dependencies
    apt-get install -y g++ zlib1g-dev nlohmann-json3-dev gzip

    # Create user
    useradd -m -s /bin/bash user || true

    # Create task directory and files
    mkdir -p /home/user/log_dumps
    cd /home/user/log_dumps

    cat << 'EOF' > node1.json
{"node_id": "node1", "status": "ACTIVE", "metrics": {"total_size": 1024}}
EOF

    cat << 'EOF' > node2.json
{"node_id": "node2", "status": "ARCHIVED", "metrics": {"total_size": 2048}}
EOF

    cat << 'EOF' > node3.json
{"node_id": "node3", "status": "ARCHIVED", "metrics": {"total_size": 4096}}
EOF

    cat << 'EOF' > node4.json
{"node_id": "node4", "status": "ACTIVE", "metrics": {"total_size": 512}}
EOF

    cat << 'EOF' > node5.json
{"node_id": "node5", "status": "ARCHIVED", "metrics": {"total_size": 8192}}
EOF

    # Compress them
    gzip *.json

    # Set permissions
    chmod -R 777 /home/user
