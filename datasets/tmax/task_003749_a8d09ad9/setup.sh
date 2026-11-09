#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl tar
    pip3 install pytest flask redis

    mkdir -p /app/ingestion
    mkdir -p /home/user/staging

    # Create Nginx config
    cat << 'EOF' > /app/ingestion/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /upload {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Create worker.env
    cat << 'EOF' > /app/ingestion/worker.env
REDIS_PORT=6380
EOF

    # Create app.py
    cat << 'EOF' > /app/ingestion/app.py
from flask import Flask, request
import redis, uuid, os

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if file:
        job_id = str(uuid.uuid4())
        path = f"/tmp/{job_id}.tar.gz"
        file.save(path)
        r.lpush('jobs', path)
        return "OK\n"
    return "No file\n", 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create worker.py
    cat << 'EOF' > /app/ingestion/worker.py
import redis, os, tarfile, time

port = int(os.environ.get('REDIS_PORT', 6380))
try:
    r = redis.Redis(host='127.0.0.1', port=port, db=0)
    while True:
        try:
            job = r.brpop('jobs', timeout=1)
            if job:
                path = job[1].decode('utf-8')
                job_id = os.path.basename(path).replace('.tar.gz', '')
                out_dir = f"/home/user/staging/{job_id}"
                os.makedirs(out_dir, exist_ok=True)
                with tarfile.open(path, "r:gz") as tar:
                    tar.extractall(path=out_dir)
        except Exception:
            pass
        time.sleep(1)
except Exception:
    pass
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/ingestion/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/ingestion/nginx.conf
export FLASK_APP=/app/ingestion/app.py
nohup flask run --port=5000 > /dev/null 2>&1 &
export $(cat /app/ingestion/worker.env | xargs)
nohup python3 /app/ingestion/worker.py > /dev/null 2>&1 &
EOF
    chmod +x /app/ingestion/start_services.sh

    # Create sample dataset
    mkdir -p /tmp/sample_dataset
    echo "hello world" > /tmp/sample_dataset/data.txt
    cat << 'EOF' > /tmp/sample_dataset/manifest.txt
Filename: data.txt
Category: docs
SHA256: b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
---
EOF
    tar -czf /app/sample_dataset.tar.gz -C /tmp sample_dataset

    # Create oracle_linker
    cat << 'EOF' > /app/oracle_linker
#!/usr/bin/env python3
import sys, os, hashlib

def get_sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    src_dir = sys.argv[1]
    tgt_dir = sys.argv[2]
    manifest = os.path.join(src_dir, 'manifest.txt')
    if not os.path.exists(manifest):
        sys.exit(0)

    records = []
    with open(manifest, 'r') as f:
        content = f.read().split('---')
        for block in content:
            block = block.strip()
            if not block: continue
            rec = {}
            for line in block.split('\n'):
                if ':' in line:
                    k, v = line.split(':', 1)
                    rec[k.strip()] = v.strip()
            if 'Filename' in rec and 'Category' in rec and 'SHA256' in rec:
                records.append(rec)

    for rec in records:
        fname = rec['Filename']
        cat = rec['Category']
        expected_hash = rec['SHA256']

        found_path = None
        for root, dirs, files in os.walk(src_dir):
            if fname in files:
                found_path = os.path.join(root, fname)
                break

        if found_path:
            actual_hash = get_sha256(found_path)
            if actual_hash == expected_hash:
                cat_dir = os.path.join(tgt_dir, cat)
                os.makedirs(cat_dir, exist_ok=True)
                tgt_path = os.path.join(cat_dir, fname)
                if not os.path.exists(tgt_path):
                    os.link(found_path, tgt_path)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_linker

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/ingestion /home/user/staging
    chmod -R 777 /home/user
