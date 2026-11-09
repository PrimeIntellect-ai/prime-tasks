#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils sed grep findutils
    pip3 install pytest

    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/raw_logs/server_alpha.jsonl
{"ts": 3600, "mutations": 2, "info": "ok"}
{"ts": 3700, "mutations": 1, "info": "error \uZZZZ"}
{"ts": 7250, "mutations": 5, "info": "ok"}
{"ts": 14400, "mutations": 3, "info": "ok"}
EOF

    cat << 'EOF' > /home/user/raw_logs/server_beta.jsonl
{"ts": 36000, "mutations": 10, "info": "ok"}
{"ts": 36500, "mutations": 10, "info": "error \uZZZZ"}
{"ts": 39600, "mutations": 5, "info": "ok"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
