#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        nginx \
        redis-server \
        redis-tools \
        curl \
        psmisc

    pip3 install pytest flask redis

    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/filter
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9091;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/backend/config.json
{
    "redis_host": "127.0.0.1",
    "redis_port": 6380
}
EOF

    cat << 'EOF' > /home/user/app/backend/backend.py
import json
import subprocess
import tempfile
import redis
import os
from flask import Flask, request

app = Flask(__name__)

with open(os.path.join(os.path.dirname(__file__), 'config.json')) as f:
    config = json.load(f)

r = redis.Redis(host=config['redis_host'], port=config['redis_port'])

@app.route('/api/submit', methods=['POST'])
def submit():
    payload = request.get_data().decode('utf-8')
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
        tmp.write(payload)
        tmp_name = tmp.name

    try:
        res = subprocess.run(['/home/user/app/filter/sanitizer', tmp_name], capture_output=True)
        if res.returncode == 0:
            r.set('last_payload', payload)
            return "Success", 200
        else:
            return "Rejected", 403
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090)
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
pkill nginx
pkill -f backend.py
pkill redis-server

redis-server --daemonize yes
nginx -c /home/user/app/nginx/nginx.conf
cd /home/user/app/backend && nohup python3 backend.py > backend.log 2>&1 &
EOF
    chmod +x /home/user/app/start.sh

    echo "Hello world" > /home/user/corpora/clean/clean1.txt
    echo "Just some normal text" > /home/user/corpora/clean/clean2.txt

    echo "Check out my ../ dir" > /home/user/corpora/evil/evil1.txt
    echo "Hello <script>alert(1)</script>" > /home/user/corpora/evil/evil2.txt
    echo "SELECT * FROM users; DROP TABLE admin;" > /home/user/corpora/evil/evil3.txt
    echo "I am $(whoami)" > /home/user/corpora/evil/evil4.txt
    echo "Nothing to see here ; rm -rf /" > /home/user/corpora/evil/evil5.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
