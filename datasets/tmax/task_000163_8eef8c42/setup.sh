#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx
    pip3 install pytest requests redis

    mkdir -p /home/user/schemas
    mkdir -p /app
    mkdir -p /tmp/project_logs

    echo '{"version": "1.0", "description": "Dummy schema"}' > /home/user/schemas/schema.json

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 80;
        server_name localhost;
        root /var/www/html;
    }
}
EOF

    cat << 'EOF' > /home/user/start_generator.sh
#!/bin/bash
# Dummy generator script
echo "Starting generator..."
python3 /app/generator.py &
EOF
    chmod +x /home/user/start_generator.sh

    cat << 'EOF' > /app/generator.py
import time
import os
while True:
    with open('/tmp/project_logs/live.log', 'a') as f:
        f.write('[WAL_START] TXN=1\nENCODING=utf-8\nTest payload\n[WAL_END] 1\n')
    time.sleep(1)
EOF

    cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import sys
import json
import gzip
import binascii

def parse_wal(filepath):
    try:
        if filepath.endswith('.gz'):
            with gzip.open(filepath, 'rt', encoding='utf-8') as f:
                lines = f.readlines()
        else:
            with open(filepath, 'r', encoding='utf-8') as f:
                lines = f.readlines()
    except Exception:
        return []

    transactions = []
    in_txn = False
    current_txn = None
    current_encoding = None
    payload_lines = []

    for line in lines:
        line = line.strip('\n')
        if line.startswith('[WAL_START] TXN='):
            in_txn = True
            current_txn = line.split('=', 1)[1]
            current_encoding = None
            payload_lines = []
        elif in_txn and line.startswith('ENCODING='):
            current_encoding = line.split('=', 1)[1]
        elif in_txn and line.startswith('[WAL_END] '):
            end_txn = line.split(' ', 1)[1]
            if end_txn == current_txn:
                payload_str = '\n'.join(payload_lines)
                if current_encoding == 'utf-16le':
                    try:
                        payload_bytes = binascii.unhexlify(payload_str.replace('\n', ''))
                        payload_str = payload_bytes.decode('utf-16le')
                    except Exception:
                        pass
                transactions.append({
                    "transaction_id": current_txn,
                    "payload": payload_str.strip()
                })
            in_txn = False
        elif in_txn:
            payload_lines.append(line)

    return transactions

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(json.dumps(parse_wal(sys.argv[1])))
    else:
        print("[]")
EOF
    chmod +x /app/oracle_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /tmp/project_logs /app
