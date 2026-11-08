#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget git gawk jq
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup JSON.sh
    mkdir -p /app/vendored/JSON.sh-0.4.1
    wget -qO /app/vendored/JSON.sh-0.4.1/JSON.sh https://raw.githubusercontent.com/dominictarr/JSON.sh/master/JSON.sh
    chmod +x /app/vendored/JSON.sh-0.4.1/JSON.sh

    # Apply perturbation to JSON.sh
    python3 -c '
import re
path = "/app/vendored/JSON.sh-0.4.1/JSON.sh"
with open(path, "r") as f:
    data = f.read()
# Replace hex unicode match with digit-only match
data = re.sub(r"\[0-9a-fA-F\]\\\\?\{4\\\\?\}", r"[0-9]{4}", data)
data = re.sub(r"\[0-9a-fA-F\]\{4\}", r"[0-9]{4}", data)
# Ensure the exact string expected by the test is present if regex missed it
if "\\\\u[0-9]{4}" not in data:
    data = data.replace(r"\\u[0-9a-fA-F]\{4\}", r"\\u[0-9]{4}")
with open(path, "w") as f:
    f.write(data)
'

    # Create corpus directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate clean logs
    cat << 'EOF' > /app/corpus/clean/clean1.jsonl
{"id": 1, "timestamp": "2023-10-12T10:00:00Z", "msg": "ok \u2713"}
{"id": 2, "timestamp": "2023-10-12T10:01:00Z", "msg": "ok"}
EOF

    # Generate evil logs
    cat << 'EOF' > /app/corpus/evil/evil_unicode.jsonl
{"id": 1, "timestamp": "2023-10-12T10:00:00Z", "msg": "bad \u12ZZ"}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_time.jsonl
{"id": 1, "timestamp": "2023-10-12T10:05:00Z", "msg": "ok"}
{"id": 2, "timestamp": "2023-10-12T10:02:00Z", "msg": "time jump backward"}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
