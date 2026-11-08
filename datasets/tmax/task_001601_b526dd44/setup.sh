#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    {"timestamp": "2023-11-01T08:15:00", "user_id": "u1", "chat_room": "general", "message": "Good morning!\nEveryone."},
    {"timestamp": "2023-11-01T08:45:00", "user_id": "u2", "chat_room": "general", "message": "こんにちは"},
    {"timestamp": "2023-11-01T09:10:00", "user_id": "u1", "chat_room": "dev", "message": "Code is broken 😭"},
    {"timestamp": "2023-11-01T10:05:00", "user_id": "u3", "chat_room": "general", "message": "Fixed.\n\nReady for review."},
    {"timestamp": "2023-11-01T12:30:00", "user_id": "u2", "chat_room": "dev", "message": "LGTM 👍"},
]

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_chat.csv', index=False, quoting=1)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
