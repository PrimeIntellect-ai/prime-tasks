#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install --default-timeout=100 pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/config_changes.jsonl
{"ts": 1, "states": {"srv_alpha": {"load": 2.0, "mem": 16}, "srv_beta": {"load": 4.0, "mem": 32}}, "note": "start\uZZZZ"}
{"ts": 2, "states": {"srv_alpha": {"load": 4.0, "mem": 16}, "srv_beta": {"load": 6.0, "mem": 32}}, "note": "update\uXX99here"}
{"ts": 3, "states": {"srv_alpha": {"load": 6.0, "mem": 16}, "srv_beta": {"load": 2.0, "mem": 32}}, "note": "normal"}
{"ts": 4, "states": {"srv_alpha": {"load": 1.0, "mem": 16}, "srv_beta": {"load": 8.0, "mem": 32}}, "note": "\u0000bad"}
EOF

    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
