#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/process_logs.py
import os
import json

if os.environ.get('LOG_REGION') != 'us-east-1':
    raise RuntimeError("Environment misconfiguration: LOG_REGION must be set to 'us-east-1'")

class LogFormatError(Exception):
    pass

def process_line(line):
    data = json.loads(line)
    return data.get('status', 'unknown')

def main(log_file):
    with open(log_file, 'r') as f:
        for line in f:
            process_line(line)

if __name__ == '__main__':
    main('/home/user/server.log')
EOF

    cat << 'EOF' > /home/user/generate_logs.py
import json

with open('/home/user/server.log', 'w') as f:
    for i in range(1000):
        if i == 742:
            f.write('{"status": "error", "timestamp": "2023-10-12T10:00:00Z", "data": corrupted}\n')
        else:
            f.write(json.dumps({"status": "ok", "timestamp": "2023-10-12T10:00:00Z", "id": i}) + '\n')
EOF

    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
