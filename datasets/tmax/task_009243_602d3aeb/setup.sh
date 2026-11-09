#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/workflow.json
{
  "experiments": [
    {"id": "exp1", "c": 1.0},
    {"id": "exp2", "c": 2.0},
    {"id": "exp3", "c": 5.0},
    {"id": "exp4", "c": 10.0}
  ]
}
EOF

    chmod -R 777 /home/user
