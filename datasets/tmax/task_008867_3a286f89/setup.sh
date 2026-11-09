#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest scipy pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/etl_output

    cat << 'EOF' > /tmp/generate_data.py
import os
import json
import random

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/etl_output', exist_ok=True)

random.seed(42)
words = ["hello", "world", "this", "is", "a", "test", "message", "please", "help", "me", "with", "my", "account", "thanks", "bye"]

with open('/home/user/data/raw_logs.jsonl', 'w') as f:
    for i in range(500):
        group = "A" if i % 2 == 0 else "B"
        num_tokens = random.randint(5, 20)
        text = " ".join(random.choices(words, k=num_tokens))
        text += random.choice([".", "!", "?", ",,,", "!!!"])

        if group == "A":
            res_time = random.normalvariate(50, 10)
        else:
            res_time = random.normalvariate(45, 10)

        f.write(json.dumps({
            "id": i,
            "text": text,
            "experiment_group": group,
            "resolution_time": res_time
        }) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
