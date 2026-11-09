#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/interactions.jsonl
{"source_node": "aaron", "target_node": "bella", "interaction_type": "follows"}
{"source_node": "bella", "target_node": "carlos", "interaction_type": "follows"}
{"source_node": "carlos", "target_node": "aaron", "interaction_type": "follows"}
{"source_node": "aaron", "target_node": "diana", "interaction_type": "likes"}
{"source_node": "carlos", "target_node": "elena", "interaction_type": "follows"}
{"source_node": "elena", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "carlos", "interaction_type": "follows"}
{"source_node": "greg", "target_node": "hannah", "interaction_type": "follows"}
{"source_node": "hannah", "target_node": "ivan", "interaction_type": "follows"}
{"source_node": "ivan", "target_node": "greg", "interaction_type": "follows"}
{"source_node": "bella", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "ivan", "interaction_type": "follows"}
{"source_node": "ivan", "target_node": "bella", "interaction_type": "follows"}
{"source_node": "aaron", "target_node": "elena", "interaction_type": "follows"}
{"source_node": "elena", "target_node": "greg", "interaction_type": "follows"}
{"source_node": "greg", "target_node": "aaron", "interaction_type": "follows"}
{"source_node": "carlos", "target_node": "diana", "interaction_type": "follows"}
{"source_node": "diana", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "diana", "interaction_type": "follows"}
EOF

    chmod -R 777 /home/user
