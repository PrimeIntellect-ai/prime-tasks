#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/generate_logs.py
import json
import random

random.seed(101)
vocab = ["the", "system", "is", "running", "smoothly", "with", "no", "issues", "critical", "error", "failed", "disk", "cpu", "memory", "usage", "high", "low", "ok"]

with open("/home/user/data/logs.jsonl", "w") as f:
    for i in range(500):
        # Generate some text
        num_words = random.randint(10, 30)
        words = random.choices(vocab, k=num_words)

        # Add some punctuation to test tokenization
        text = " ".join(words) + random.choice([".", "!", "?", ""])
        if random.random() < 0.1:
            text += " CRITICAL!!!"

        f.write(json.dumps({"id": i, "text": text}) + "\n")
EOF
    python3 /home/user/data/generate_logs.py

    cat << 'EOF' > /home/user/verify.py
import json
import math
import sys

def verify():
    try:
        with open("/home/user/etl_tester/output.json", "r") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Failed to read output.json: {e}")
        sys.exit(1)

    mean = data.get("mean_frequency")
    se = data.get("standard_error")

    if mean is None or se is None:
        print("Missing keys in output.json")
        sys.exit(1)

    if not (0.04 < mean < 0.08):
        print(f"Mean frequency {mean} is out of expected bounds.")
        sys.exit(1)

    if not (0.001 < se < 0.015):
        print(f"Standard error {se} is out of expected bounds.")
        sys.exit(1)

    print("Success")
    sys.exit(0)

if __name__ == "__main__":
    verify()
EOF

    chmod -R 777 /home/user
