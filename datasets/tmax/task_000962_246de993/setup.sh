#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl gawk
    pip3 install pytest flask redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/app/flask
    mkdir -p /home/user/app/logs
    mkdir -p /home/user/eval_logs

    # Create dummy nginx config
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    access_log /home/user/app/logs/access.log;
    error_log /home/user/app/logs/error.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://1.2.3.4:9999; # dummy placeholder
        }
    }
}
EOF

    # Create dummy flask config
    cat << 'EOF' > /home/user/app/flask/config.py
REDIS_HOST = "dummy.placeholder.internal"
REDIS_PORT = 6379
EOF

    # Create flask app
    cat << 'EOF' > /home/user/app/flask/app.py
from flask import Flask, request, jsonify
import config
import redis

app = Flask(__name__)
try:
    r = redis.Redis(host=config.REDIS_HOST, port=config.REDIS_PORT)
except:
    r = None

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    auth = request.headers.get('Authorization')
    if not auth or auth != "Bearer valid_token":
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"message": "Success", "path": path}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Generate evaluation logs and ground truth
    cat << 'EOF' > /tmp/gen_logs.py
import random

ips = [f"192.168.1.{i}" for i in range(1, 101)]
malicious_ips = set()

with open("/home/user/eval_logs/access.log", "w") as f:
    # 1. Path traversal
    mal_ip1 = ips[10]
    malicious_ips.add(mal_ip1)
    f.write(f'{mal_ip1} - - [10/Oct/2023:13:55:36 -0700] "GET /api/data?file=../../etc/passwd HTTP/1.1" 200 123 "-" "curl"\n')

    mal_ip2 = ips[11]
    malicious_ips.add(mal_ip2)
    f.write(f'{mal_ip2} - - [10/Oct/2023:13:55:36 -0700] "GET /api/data?file=%2e%2e%2fetc/passwd HTTP/1.1" 200 123 "-" "curl"\n')

    # 2. SQLi
    mal_ip3 = ips[20]
    malicious_ips.add(mal_ip3)
    f.write(f'{mal_ip3} - - [10/Oct/2023:13:55:37 -0700] "GET /api/data?q=UNION%20SELECT%20* HTTP/1.1" 200 123 "-" "curl"\n')

    # 3. RCE
    mal_ip4 = ips[30]
    malicious_ips.add(mal_ip4)
    f.write(f'{mal_ip4} - - [10/Oct/2023:13:55:38 -0700] "GET /api/data?cmd=;%20rm%20-rf%20/ HTTP/1.1" 200 123 "-" "curl"\n')

    mal_ip5 = ips[31]
    malicious_ips.add(mal_ip5)
    f.write(f'{mal_ip5} - - [10/Oct/2023:13:55:38 -0700] "GET /api/data?cmd=$(whoami) HTTP/1.1" 200 123 "-" "curl"\n')

    # 4. >50 401s
    mal_ip6 = ips[40]
    malicious_ips.add(mal_ip6)
    for _ in range(55):
        f.write(f'{mal_ip6} - - [10/Oct/2023:13:55:39 -0700] "GET /api/data HTTP/1.1" 401 123 "-" "curl"\n')

    # Normal traffic
    for _ in range(4000):
        ip = random.choice(ips[50:])
        status = random.choice([200, 200, 200, 404])
        f.write(f'{ip} - - [10/Oct/2023:13:55:40 -0700] "GET /api/data HTTP/1.1" {status} 123 "-" "curl"\n')

with open("/home/user/eval_logs/truth.txt", "w") as f:
    for ip in malicious_ips:
        f.write(f"{ip}\n")
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
