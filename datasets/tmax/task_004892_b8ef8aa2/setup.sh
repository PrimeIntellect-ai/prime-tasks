#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'JSONL' > /home/user/raw_data.jsonl
{"user_id": "u001", "status": "completed", "items": [{"price": 10.5, "quantity": 2}, {"price": 5.0, "quantity": 1}]}
{"user_id": "u002", "status": "pending", "items": [{"price": 100.0, "quantity": 1}]}
{"user_id": "u003", "status": "completed", "total_amount": 45.5}
{"user_id": "u001", "status": "completed", "total_amount": 14.0}
{"user_id": "u004", "status": "completed", "items": [{"price": 0.0, "quantity": 5}]}
{"user_id": "u005", "status": "completed", "items": []}
{"user_id": "u006", "status": "refunded", "total_amount": -20.0}
{"user_id": "u007", "status": "completed", "total_amount": 0}
JSONL

    chmod -R 777 /home/user
