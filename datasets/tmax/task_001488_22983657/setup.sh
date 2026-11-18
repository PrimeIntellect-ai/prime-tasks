#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.json
[
  {"id": 1, "b64_payload": "U3lzdGVtIGJvb3RlZCBzdWNjZXNzZnVsbHk="},
  {"id": 2, "b64_payload": "Q3JpdGljYWwgZXJyb3I6IEFLaWV5IGlzIGZha2UgQUtJQUlPU0ZPRE5ON0VYQU1QTEUgdXNlZCA="},
  {"id": 3, "b64_payload": "QUtJQVRFU1QxMjM0NTY3ODkwMTIgYW5kIEFLSUFaWEZWMjM0NTY3ODkwMTIz"}
]
EOF

    chmod -R 777 /home/user
