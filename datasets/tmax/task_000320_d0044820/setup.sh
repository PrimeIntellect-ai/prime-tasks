#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nginx redis-server
    pip3 install pytest requests numpy

    mkdir -p /app/data
    mkdir -p /app/eval/corpus/clean
    mkdir -p /app/eval/corpus/evil
    mkdir -p /home/user/ingest_api

    # Generate historical data
    cat << 'EOF' > /app/data/historical.csv
transaction_id,timestamp,category,amount
1,1620000000,A,100.5
2,1620000001,B,200.0
3,1620000002,C,300.5
EOF

    # Create dummy corpora
    touch /app/eval/corpus/clean/1.csv
    touch /app/eval/corpus/evil/1.csv

    # Generate verify.py
    cat << 'EOF' > /app/eval/verify.py
import requests
print("Verified")
EOF

    # Configure nginx
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    location / {
        proxy_pass http://127.0.0.1:9000;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
