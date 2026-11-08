#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl jq
    pip3 install pytest flask requests

    mkdir -p /home/user/workspace/projects

    cat << 'EOF' > /home/user/workspace/projects/utils.json
{"module": "utils", "cost": 10, "dependencies": []}
EOF

    cat << 'EOF' > /home/user/workspace/projects/db.json
{"module": "db", "cost": 20, "dependencies": ["utils"]}
EOF

    cat << 'EOF' > /home/user/workspace/projects/auth.json
{"module": "auth", "cost": 15, "dependencies": ["db"]}
EOF

    cat << 'EOF' > /home/user/workspace/projects/api.json
{"module": "api", "cost": 30, "dependencies": ["auth", "utils"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
