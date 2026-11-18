#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx curl
    pip3 install pytest fastapi uvicorn redis scipy numpy requests httpx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/populate_redis.py
import redis
import json
import numpy as np

r = redis.Redis(host='127.0.0.1', port=6379, db=0)
r.delete('raw_telemetry')

np.random.seed(42)
for i in range(500):
    score_A = np.random.normal(80, 10)
    r.rpush('raw_telemetry', json.dumps({"user_id": f"uA_{i}", "group": "A", "score": score_A}))

for i in range(500):
    score_B = np.random.normal(82, 12)
    r.rpush('raw_telemetry', json.dumps({"user_id": f"uB_{i}", "group": "B", "score": score_B}))
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
daemon off;
error_log /tmp/nginx_error.log;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log off;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    server {
        listen 8080;
        server_name localhost;

        # TODO: Add location /api/ routing rules here
    }
}
EOF

    cat << 'EOF' > /home/user/app/api.py
from fastapi import FastAPI, Header, HTTPException
import redis
import json
import numpy as np
from scipy import stats

app = FastAPI()

# TODO: Implement GET /stats endpoint
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx.conf &
cd /home/user/app && uvicorn api:app --host 127.0.0.1 --port 8000 &
sleep 2
EOF

    chmod +x /home/user/app/start_services.sh
    chmod -R 777 /home/user
