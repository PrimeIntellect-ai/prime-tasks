#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/capture.json
[
  {"user": "admin", "token": "N2E2MzQxMjViMDc4NTA1NTA1ZTYwZDkyZWE0MDc5OGU="},
  {"user": "guest", "token": "MWM4ZDkzZWMwOGExYTViMjIzMWIyMTliNDFmYzgxYzQ="},
  {"user": "operator", "token": "MWZhYzcxMmZlYTI4ZmZkNDEzMmRiODJiMTgyNWMyNGQ="}
]
EOF

    cd /home/user
    sha256sum capture.json > capture.json.sha256

    chmod -R 777 /home/user
