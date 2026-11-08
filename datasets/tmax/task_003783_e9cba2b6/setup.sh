#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app/logs /app/config /app/oracle

    # Create logs
    cat << 'EOF' > /app/logs/access.log
[2023-10-25 10:00:01] 192.168.1.10 - Mozilla/5.0 - SessionID:tok_valid_1 - /api/data
[2023-10-25 10:00:05] 10.0.0.5 - EvilBot/1.0 - SessionID:tok_compromised_a - /api/admin
[2023-10-25 10:01:00] 192.168.1.11 - Mozilla/5.0 - SessionID:tok_valid_2 - /api/data
[2023-10-25 10:01:05] 10.0.0.6 - EvilBot/1.0 - SessionID:tok_compromised_b - /api/admin
EOF

    # Create initial config
    cat << 'EOF' > /app/config/settings.json
{
  "api_secret": "old_md5_secret_123",
  "port": 5000
}
EOF

    # Start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
/app/start_flask.sh &
EOF
    chmod +x /app/start.sh

    # Flask start script
    cat << 'EOF' > /app/start_flask.sh
#!/bin/bash
# Mock of the flask server startup
python3 /app/flask_app.py
EOF
    chmod +x /app/start_flask.sh

    # Mock flask app
    touch /app/flask_app.py

    # Reference Oracle (Python script wrapper simulating a binary)
    cat << 'EOF' > /app/oracle/reference_token_gen
#!/usr/bin/env python3
import hmac
import hashlib
import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--user', required=True)
parser.add_argument('--time', required=True)
args = parser.parse_args()

secret = b"Secr3t_HMAC_v2_991"
msg = f"{args.user}:{args.time}".encode('utf-8')
digest = hmac.new(secret, msg, hashlib.sha256).hexdigest()
sys.stdout.write(digest)
EOF
    chmod +x /app/oracle/reference_token_gen

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
