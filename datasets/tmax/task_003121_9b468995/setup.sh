#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install --default-timeout=100 pytest flask gunicorn redis scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /app/nginx /app/api /app/redis /app/logs

    cat << 'EOF' > /app/api/app.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/api/v1/search')
def search():
    query = request.args.get('q', '')
    if not query:
        return jsonify([])

    # ROOT CAUSE: Using KEYS with wildcards blocks Redis
    matched_keys = r.keys(f"{query}*")
    results = []
    for k in matched_keys[:50]:
        results.append(k.decode('utf-8'))
    return jsonify(results)

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
error_log /app/logs/nginx-error.log;
pid /app/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /app/logs/nginx-access.log;
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_read_timeout 2s;
        }
    }
}
EOF

    cat << 'EOF' > /app/redis/redis.conf
port 6379
bind 127.0.0.1
dir /app/redis
logfile /app/logs/redis.log
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
mkdir -p /app/logs
redis-server /app/redis/redis.conf &
sleep 1
python3 -c "
import redis
try:
    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    if r.dbsize() < 100000:
        pipe = r.pipeline()
        for i in range(200000):
            pipe.set(f'test_prefix_{i}', '1')
            if i % 10000 == 0:
                pipe.execute()
        pipe.execute()
except:
    pass
" &
gunicorn -w 4 -b 127.0.0.1:5000 --chdir /app/api app:app --daemon --access-logfile /app/logs/api.log --error-logfile /app/logs/api.log
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/stop.sh
#!/bin/bash
pkill -f gunicorn
nginx -c /app/nginx/nginx.conf -s stop || true
redis-cli shutdown || true
EOF
    chmod +x /app/stop.sh

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = []
for _ in range(10):
    pkts.append(IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="GET /api/v1/search?q=normal HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
for _ in range(3):
    pkts.append(IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="GET /api/v1/search?q=test_prefix*** HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
wrpcap('/home/user/incident.pcap', pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
