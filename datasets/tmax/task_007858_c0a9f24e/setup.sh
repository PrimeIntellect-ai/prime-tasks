#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.jsonl
{"ts": 1600000002, "lat": 10}
{"ts": 1600000005, "lat": 20}
{"ts": 1600000022, "lat": 50}
{"ts": 1600000035, "lat": 100}
{"ts": 1600000036, "lat": 200}
{"ts": 1600000060, "lat": 10}
EOF

    chown user:user /home/user/requests.jsonl
    chmod -R 777 /home/user
