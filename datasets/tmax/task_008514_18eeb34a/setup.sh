#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/organized_data /home/user/archives

    cat << 'EOF' > /home/user/stream_generator.py
#!/usr/bin/env python3
import sys
import json
import random

def generate():
    experiments = ["EXP_ALPHA", "EXP_BETA", "EXP_GAMMA"]
    random.seed(42) # Deterministic for verification

    for i in range(1000):
        if i % 100 == 0:
            sys.stdout.write("CORRUPTED_LINE_" + str(i) + "{missing_brackets}\n")
        else:
            exp = random.choice(experiments)
            record = {
                "experiment_id": exp,
                "read_id": f"READ_{i}",
                "sequence_data": "".join(random.choices(["A", "C", "G", "T"], k=50))
            }
            sys.stdout.write(json.dumps(record) + "\n")

if __name__ == "__main__":
    generate()
EOF

    chmod +x /home/user/stream_generator.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
