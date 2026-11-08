#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest fastapi uvicorn celery redis python-multipart

    mkdir -p /app/localization_pipeline
    mkdir -p /app/tests/corpora/evil
    mkdir -p /app/tests/corpora/clean

    cat << 'EOF' > /app/localization_pipeline/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /upload {
            # proxy_pass missing
        }
    }
}
EOF

    cat << 'EOF' > /app/localization_pipeline/receiver.py
import os
from fastapi import FastAPI, UploadFile, File
from celery import Celery
import json

app = FastAPI()

REDIS_URL = ""
celery_app = Celery('tasks', broker=REDIS_URL)

@celery_app.task(name='process_file')
def process_file(content):
    with open('/home/user/processed_stats.json', 'w') as f:
        json.dump({"status": "done"}, f)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    content = await file.read()
    celery_app.send_task('process_file', args=[content.decode('utf-8')])
    return {"status": "queued"}
EOF

    cat << 'EOF' > /app/localization_pipeline/restart_services.sh
#!/bin/bash
cd /app/localization_pipeline
nginx -c /app/localization_pipeline/nginx.conf -s stop 2>/dev/null || true
nginx -c /app/localization_pipeline/nginx.conf
pkill -f uvicorn || true
nohup uvicorn receiver:app --host 127.0.0.1 --port 5000 > uvicorn.log 2>&1 &
redis-server --daemonize yes
pkill -f celery || true
nohup celery -A receiver.celery_app worker --loglevel=info > celery.log 2>&1 &
EOF
    chmod +x /app/localization_pipeline/restart_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
