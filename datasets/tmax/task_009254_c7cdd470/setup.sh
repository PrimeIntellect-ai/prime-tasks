#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    # Create directory structure
    mkdir -p /home/user/backups/raw

    # Populate initial JSON files
    cat << 'EOF' > /home/user/backups/raw/user_1.json
{"id": 1, "name": "Aaron", "email": "aaron@example.com", "role": "admin"}
EOF

    cat << 'EOF' > /home/user/backups/raw/user_2.json
{"id": 2, "name": "Betty", "email": "betty.boo@test.org", "location": "NY"}
EOF

    cat << 'EOF' > /home/user/backups/raw/user_3.json
{"id": 3, "name": "Charlie", "email": "charlie@domain.net"}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
