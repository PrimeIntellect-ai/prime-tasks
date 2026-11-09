#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/reports

    cat << 'EOF' > /home/user/reports/node1.json
[{"project_id": 101, "storage_used_mb": 500}, {"project_id": 102, "storage_used_mb": 1500}]
EOF

    cat << 'EOF' > /home/user/reports/node2.json
[{"project_id": 101, "storage_used_mb": 250}, {"project_id": 103, "storage_used_mb": 3000}]
EOF

    cat << 'EOF' > /home/user/project_totals.csv
101,1000
104,500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
