#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/services

    cat << 'EOF' > /app/corpus/clean/clean_logs.jsonl
{"timestamp": "2023-10-12T07:20:50.52Z", "status_code": 200, "message": "All good"}
{"timestamp": "2023-10-12T07:21:50.52Z", "status_code": 404, "nested": {"key": "value"}}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_logs.jsonl
{"timestamp": "2023-10-12T07:20:50.52Z", "status_code": 600, "message": "Bad status"}
{"timestamp": "2023-10-12 07:20:50", "status_code": 200, "message": "Bad timestamp"}
{"timestamp": "2023-10-12T07:20:50.52Z", "status_code": 200, "message": "hello <script>alert(1)</script>"}
{"timestamp": "2023-10-12T07:20:50.52Z", "status_code": 200, "query": "DROP TABLE users"}
EOF

    cat << 'EOF' > /app/services/producer.py
#!/usr/bin/env python3
import time
import sys
import json

def main():
    pass

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/services/producer.py

    cat << 'EOF' > /app/services/consumer.py
#!/usr/bin/env python3
import time
import sys

def main():
    pass

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/services/consumer.py

    cat << 'EOF' > /app/services/start_pipeline.sh
#!/bin/bash
rm -f /tmp/raw_logs.fifo /tmp/clean_logs.fifo
mkfifo /tmp/raw_logs.fifo
mkfifo /tmp/clean_logs.fifo

python3 /app/services/producer.py &
python3 /app/services/consumer.py &
EOF
    chmod +x /app/services/start_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
