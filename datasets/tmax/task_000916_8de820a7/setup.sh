#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv binutils
pip3 install pytest pyinstaller

mkdir -p /app
mkdir -p /home/user

# Create the embedder script
cat << 'EOF' > /tmp/embedder.py
import sys
import json
import random
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', required=True)
    parser.add_argument('-o', '--output', required=True)
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        data = json.load(f)

    with open(args.output, 'w') as f:
        for s in data:
            if len(s) > 0:
                seed = len(s) + ord(s[0])
            else:
                seed = 0
            random.seed(seed)
            row = [random.uniform(-1.0, 1.0) for _ in range(1024)]
            f.write(','.join(map(str, row)) + '\n')

if __name__ == '__main__':
    main()
EOF

# Compile the embedder into a standalone binary
cd /tmp
pyinstaller --onefile embedder.py
mv dist/embedder /app/log_embedder
chmod +x /app/log_embedder
strip /app/log_embedder

# Generate logs and labels
cat << 'EOF' > /tmp/generate_data.py
import json
import random

logs = []
labels = []
for i in range(500):
    log_type = random.choice(["INFO", "ERROR", "WARN", "DEBUG"])
    msg = f"{log_type}: Message {i}"
    logs.append(msg)

    seed = len(msg) + ord(msg[0])
    random.seed(seed)
    val = random.uniform(-1.0, 1.0)
    labels.append(1 if val > 0 else 0)

with open('/home/user/logs.json', 'w') as f:
    json.dump(logs, f)
with open('/home/user/labels.json', 'w') as f:
    json.dump(labels, f)
EOF

python3 /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
