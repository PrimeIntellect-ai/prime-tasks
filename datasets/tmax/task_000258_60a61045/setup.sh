#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api_test.json
{
  "instructions": [
    "PUSH 1000",
    "PUSH 500",
    "ADD",
    "PUSH 10",
    "MUL",
    "PUSH 2500",
    "SUB"
  ]
}
EOF

    chmod -R 777 /home/user
