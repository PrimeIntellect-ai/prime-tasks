#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/dirty_records.jsonl
{"id": 1, "text": "data \u202scientist"}
{"id": 2, "text": "data scientist\u12"}
{"id": 3, "text": "software engineer"}
{"id": 4, "text": "dat\ua scientist"}
{"id": 5, "text": "data \u0000scientist"}
{"id": 6, "text": "data scientist"}
{"id": 7, "text": "\udata scientist"}
{"id": 8, "text": "data \uFfFfscientist"}
{"id": 9, "text": "dba"}
{"id": 10, "text": "data \u0scientist"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
