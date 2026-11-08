#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server git curl jq
    pip3 install pytest flask redis gunicorn

    mkdir -p /app/flask_app
    mkdir -p /app/nginx
    mkdir -p /app/logs
    mkdir -p /app/worker_repo
    mkdir -p /verify/corpus/evil
    mkdir -p /verify/corpus/clean

    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf
redis-server --daemonize yes
cd /app/flask_app
gunicorn -w 1 -b 127.0.0.1:5000 app:app &
cd /app/worker_repo
python3 worker.py &
wait
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/flask_app/config.py
REDIS_HOST = "/var/run/redis.sock"
REDIS_PORT = 6379
EOF

    cat << 'EOF' > /app/flask_app/app.py
from flask import Flask, request
import redis
import config
import json

app = Flask(__name__)
r = redis.Redis(host=config.REDIS_HOST, port=config.REDIS_PORT)

@app.route('/submit', methods=['POST'])
def submit():
    data = request.json
    r.lpush('queue', json.dumps(data))
    return "OK", 200
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/tmp/flask.sock;
        }
    }
}
EOF

    cat << 'EOF' > /app/logs/worker_crash.log
Traceback (most recent call last):
  File "worker.py", line 15, in <module>
    process(payload)
  File "/app/worker_repo/normalizer.py", line 42, in normalize
    while val < 1e-300:
MemoryError
EOF

    cd /app/worker_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > normalizer.py
def normalize(val, tz):
    return val
EOF
    cat << 'EOF' > worker.py
import redis, json
from normalizer import normalize
r = redis.Redis(host='127.0.0.1', port=6379)
while True:
    _, data = r.brpop('queue')
    payload = json.loads(data)
    normalize(payload['value'], payload['tz'])
EOF
    git add .
    git commit -m "Initial commit"

    cat << 'EOF' > normalizer.py
def normalize(val, tz):
    debug_list = []
    if val < 1e-300 and "UTC-" in tz:
        while val < 1e-300:
            debug_list.append(val)
    return val
EOF
    git add normalizer.py
    git commit -m "Add precision repair logic"

    cat << 'EOF' > normalizer.py
def normalize(val, tz):
    debug_list = []
    if val < 1e-300 and "UTC-" in tz:
        while val < 1e-300:
            debug_list.append(val)
    # some other change
    return val
EOF
    git add normalizer.py
    git commit -m "Update normalizer"

    cat << 'EOF' > normalizer.py
def normalize(val, tz):
    debug_list = []
    if val < 1e-300 and "UTC-" in tz:
        while val < 1e-300:
            debug_list.append(val)
    # another change
    return val
EOF
    git add normalizer.py
    git commit -m "Fix something else"

    echo '{"sensor": "X", "value": 1e-305, "tz": "UTC-14"}' > /verify/corpus/evil/1.json
    echo '{"sensor": "X", "value": 1e-310, "tz": "UTC-10"}' > /verify/corpus/evil/2.json
    echo '{"sensor": "X", "value": 0.5, "tz": "UTC+1"}' > /verify/corpus/clean/1.json
    echo '{"sensor": "X", "value": 1.0, "tz": "UTC"}' > /verify/corpus/clean/2.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
