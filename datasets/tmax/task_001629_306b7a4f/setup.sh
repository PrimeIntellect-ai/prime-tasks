#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server cron
    pip3 install pytest flask redis gunicorn python-dotenv

    mkdir -p /home/user/app/telemetry_stack
    mkdir -p /home/user/tests/evil_corpus
    mkdir -p /home/user/tests/clean_corpus
    mkdir -p /home/user/production_logs

    # Setup telemetry stack files
    cat << 'EOF' > /home/user/app/telemetry_stack/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            proxy_pass http://127.0.0.1:80; # BROKEN: should point to Flask port
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/telemetry_stack/.env
REDIS_HOST=unknown_host
REDIS_PORT=0
EOF

    cat << 'EOF' > /home/user/app/telemetry_stack/app.py
import os
from flask import Flask, request, jsonify
import redis
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)

r = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', 6379)),
    decode_responses=True
)

@app.route('/api/record', methods=['POST'])
def record():
    data = request.json
    if not data:
        return jsonify({"error": "No data"}), 400
    try:
        r.set('last_record', str(data))
        return jsonify({"status": "success"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
EOF

    cat << 'EOF' > /home/user/app/telemetry_stack/start.sh
#!/bin/bash
# Start script for telemetry stack
# TODO: Fix this script to correctly start redis, flask, and nginx

echo "Starting telemetry stack..."
EOF
    chmod +x /home/user/app/telemetry_stack/start.sh

    # Populate evil corpus
    echo "Some normal log data" > /home/user/tests/evil_corpus/app-2023-01-01.log
    echo "DEBUG_LEVEL=5" > /home/user/tests/evil_corpus/backup-2024-05-15.bak
    echo "DEBUG_LEVEL=1\nSome other data" > /home/user/tests/evil_corpus/app-2024-05-10.log

    # Populate clean corpus
    echo "Recent normal log data" > /home/user/tests/clean_corpus/app-2024-05-14.log
    echo "AUDIT_TRAIL=true\nDEBUG_LEVEL=5" > /home/user/tests/clean_corpus/backup-2023-01-01.bak
    echo "AUDIT_TRAIL=true\nOld data" > /home/user/tests/clean_corpus/app-2020-01-01.log

    # Populate production logs with a mix
    echo "DEBUG_LEVEL=9" > /home/user/production_logs/app-2024-05-15.log
    echo "AUDIT_TRAIL=true" > /home/user/production_logs/backup-2024-05-10.bak

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
