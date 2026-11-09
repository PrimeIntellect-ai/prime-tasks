#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.jsonl
{"item_id": 10, "content": "the quick brown fox jumps over the lazy dog"}
{"item_id": 20, "content": "a quick brown fox"}
{"item_id": 30, "content": "the lazy dog sleeps all day"}
{"item_id": 40, "content": "a sleeping dog"}
{"item_id": 50, "content": "the quick brown fox jumps"}
EOF

    chmod -R 777 /home/user
