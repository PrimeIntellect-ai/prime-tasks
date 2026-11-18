#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deps.txt
frontend: api utils
api: db logger
utils: logger ui
db: config
logger: config
ui: config theme
theme:
config:
EOF

    chmod -R 777 /home/user
