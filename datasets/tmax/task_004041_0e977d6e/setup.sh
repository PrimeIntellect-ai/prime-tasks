#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/data/history
    touch /app/data/history/dummy.db /app/data/history/old_logs.txt

    mkdir -p /app/services/nginx
    cat << 'EOF' > /app/services/nginx/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /tmp/proxy_temp_path;
    fastcgi_temp_path     /tmp/fastcgi_temp;
    uwsgi_temp_path       /tmp/uwsgi_temp;
    scgi_temp_path        /tmp/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location /ingest {
            # Broken proxy pass
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    mkdir -p /app/services/api
    cat << 'EOF' > /app/services/api/app.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.get_json()
    r.lpush('capacity_queue', json.dumps(data))
    return "OK\n", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/services/api/app.py &
nginx -c /app/services/nginx/nginx.conf
EOF
    chmod +x /app/services/start_all.sh

    mkdir -p /app/corpora/evil /app/corpora/clean

    cat << 'EOF' > /app/corpora/evil/evil_logs.jsonl
{"host": "web-01", "cpu_percent": 105.0, "mem_bytes": 1024}
{"host": "web-02", "cpu_percent": 50.0, "mem_bytes": -10}
{"host": "web-01; drop table", "cpu_percent": 40.0, "mem_bytes": 2048}
{"host": "web-03", "cpu_percent": 40.0}
{"host": "web-04", "cpu_percent": 40.0, "mem_bytes": 2048, "extra": "data"}
{malformed json
EOF

    cat << 'EOF' > /app/corpora/clean/clean_logs.jsonl
{"host": "web-01", "cpu_percent": 45.5, "mem_bytes": 1024}
{"host": "db-master-1", "cpu_percent": 99.9, "mem_bytes": 8589934592}
{"host": "cache-node", "cpu_percent": 0.0, "mem_bytes": 1}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
