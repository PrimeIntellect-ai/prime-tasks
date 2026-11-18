#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.jsonl
{"id": 1, "text_a": "hallo", "text_b": "hello", "series": [0.0, null, 10.0]}
{"id": 2, "text_a": "こんにちは世界", "text_b": "こんちは世界", "series": [5.0, null, null, 20.0]}
{"id": 3, "text_a": "Привет 🌍", "text_b": "Привет 🌎", "series": [-1.0, null, -5.0]}
{"id": 4, "text_a": "résumé", "text_b": "resume", "series": [100.0, null, null, null, 200.0]}
EOF

    chmod -R 777 /home/user
