#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl docker.io docker-compose
    pip3 install pytest pandas pyarrow scikit-learn

    mkdir -p /home/user/app/nginx /home/user/app/flask

    cat << 'EOF' > /home/user/app/docker-compose.yml
version: '3.8'
services:
  nginx:
    image: nginx:latest
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
  flask:
    build: ./flask
    ports:
      - "5000:5000"
  redis:
    image: redis:latest
    ports:
      - "6379:6379"
EOF

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 80;
        location / {
            proxy_pass http://flask:5000;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/flask/app.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/')
def index():
    return json.dumps({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/app/generate_traffic.sh
#!/bin/bash
for i in {1..100}; do
    curl -s http://localhost:8080 > /dev/null
done
EOF
    chmod +x /home/user/app/generate_traffic.sh

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import uuid

all_req = []
anomalies = []

for i in range(100):
    req_id = str(uuid.uuid4())
    all_req.append({"request_id": req_id})
    if i % 10 == 0:
        anomalies.append({
            "request_id": req_id,
            "timestamp": "2023-10-01T12:00:00Z",
            "url": "/",
            "status_code": 500,
            "nginx_latency": 0.5,
            "flask_latency": 0.1,
            "anomaly_reason": "5xx"
        })

pd.DataFrame(all_req).to_parquet('/home/user/app/all_requests.parquet')
pd.DataFrame(anomalies).to_parquet('/home/user/app/ground_truth_anomalies.parquet')
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
