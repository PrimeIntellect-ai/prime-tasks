#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis requests fastapi uvicorn

    mkdir -p /home/user/app /home/user/corpus/clean /home/user/corpus/evil

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request, jsonify
import redis
import sys

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    r.incr('processed_count')
    return jsonify({"status": "success", "count": r.get('processed_count').decode()}), 200

if __name__ == '__main__':
    port = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == '--port' else 9999
    app.run(host='127.0.0.1', port=port)
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
error_log /home/user/app/error.log;
pid /home/user/app/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/app/access.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --port 6379 --daemonize yes
nginx -c /home/user/app/nginx.conf
python3 /home/user/app/api.py --port 9999 &
EOF
    chmod +x /home/user/app/start_services.sh

    # Generate corpus files using seq to ensure compatibility with /bin/sh
    for i in $(seq 1 50); do echo "{\"username\": \"user$i\", \"comment\": \"This is a safe comment $i\"}" > /home/user/corpus/clean/req_$i.json; done
    for i in $(seq 1 17); do echo "{\"username\": \"hacker$i\", \"comment\": \"Check out <script>alert(1)</script>\"}" > /home/user/corpus/evil/req_$i.json; done
    for i in $(seq 18 34); do echo "{\"username\": \"hacker$i\", \"comment\": \"Admin UNION SELECT * FROM users\"}" > /home/user/corpus/evil/req_$i.json; done
    for i in $(seq 35 50); do echo "{\"username\": \"hacker$i\", \"comment\": \"File ../etc/passwd read\"}" > /home/user/corpus/evil/req_$i.json; done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
