#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-flask \
        python3-redis \
        python3-dotenv \
        python3-numpy \
        python3-scipy \
        python3-requests \
        nginx \
        redis-server \
        gunicorn

    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/seed_redis.py
nginx -c /app/nginx.conf
gunicorn -w 1 -b 127.0.0.1:5000 --chdir /app app:app --daemon
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            # DELIBERATE ERROR: port 5001 instead of 5000
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/.env
# DELIBERATE ERROR: port 6380 instead of 6379
REDIS_PORT=6380
EOF

    cat << 'EOF' > /app/app.py
import os, redis, json
from flask import Flask, jsonify
from dotenv import load_dotenv

load_dotenv('/app/.env')
app = Flask(__name__)
r = redis.Redis(host='localhost', port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/data')
def get_data():
    data = r.get('nanopore_signal')
    if data:
        return jsonify({"signal": json.loads(data)})
    return jsonify({"error": "No data"}), 404
EOF

    cat << 'EOF' > /app/seed_redis.py
import redis, json, numpy as np
r = redis.Redis(host='localhost', port=6379)
t = np.arange(1024)
# Ground truth parameters: a=2.5, b=0.002, c=1.2, d=0.42
# Noise includes normal noise + high frequency sine waves
clean_signal = 2.5 * np.exp(-0.002 * t) + 1.2 * np.sin(0.42 * t)
noise = np.random.normal(0, 0.5, 1024) + 0.8 * np.sin(2 * np.pi * 0.3 * t) + 0.5 * np.sin(2 * np.pi * 0.45 * t)
signal = clean_signal + noise
r.set('nanopore_signal', json.dumps(signal.tolist()))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/log/nginx /var/lib/nginx || true
