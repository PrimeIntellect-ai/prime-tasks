#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl zip unzip gzip tar nginx redis-server
pip3 install pytest flask redis markdown python-dotenv

mkdir -p /app/doc_stack

cat << 'EOF' > /app/doc_stack/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location /api/render {
            # TODO: fix proxy_pass to Flask app
            return 502;
        }
    }
}
EOF

cat << 'EOF' > /app/doc_stack/app.py
import os
from flask import Flask, request
import redis
import markdown

app = Flask(__name__)
redis_host = os.environ.get("REDIS_HOST", "127.0.0.1")
cache = redis.Redis(host=redis_host, port=6379, socket_connect_timeout=1)

@app.route("/api/render", methods=["POST"])
def render():
    text = request.get_data(as_text=True)
    cache.ping()
    html = markdown.markdown(text)
    return html

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
EOF

cat << 'EOF' > /app/doc_stack/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/doc_stack/nginx.conf
export $(cat /app/doc_stack/.env | xargs)
nohup python3 /app/doc_stack/app.py > /dev/null 2>&1 &
EOF
chmod +x /app/doc_stack/start.sh

cat << 'EOF' > /app/doc_stack/requirements.txt
Flask
redis
Markdown
EOF

cat << 'EOF' > /app/doc_stack/.env
REDIS_HOST=remote.cache.internal
EOF

mkdir -p /home/user/corpora/clean
mkdir -p /home/user/corpora/evil

python3 -c '
import os
import tarfile
import gzip
import zipfile
import tempfile
import random

clean_dir = "/home/user/corpora/clean"
evil_dir = "/home/user/corpora/evil"
evil_strings = ["<script>alert(1)</script>", "<iframe src=\"evil\"></iframe>", "<!-- SYSTEM_EXEC: rm -rf / -->"]

for i in range(50):
    with tempfile.TemporaryDirectory() as td:
        md_path = os.path.join(td, "doc.md")
        with open(md_path, "w") as f:
            f.write(f"Clean docs {i} with [CONFIDENTIAL] info.\n")
        zip_path = os.path.join(td, "docs.zip")
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.write(md_path, "doc.md")
        gz_path = os.path.join(td, "payload.gz")
        with open(zip_path, "rb") as fin, gzip.open(gz_path, "wb") as fout:
            fout.writelines(fin)
        tar_path = os.path.join(clean_dir, f"bundle_{i}.tar")
        with tarfile.open(tar_path, "w") as tf:
            tf.add(gz_path, arcname="payload.gz")

for i in range(50):
    with tempfile.TemporaryDirectory() as td:
        md_path = os.path.join(td, "doc.md")
        with open(md_path, "w") as f:
            f.write(f"Evil docs {i} with {random.choice(evil_strings)}\n")
        zip_path = os.path.join(td, "docs.zip")
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.write(md_path, "doc.md")
        gz_path = os.path.join(td, "payload.gz")
        with open(zip_path, "rb") as fin, gzip.open(gz_path, "wb") as fout:
            fout.writelines(fin)
        tar_path = os.path.join(evil_dir, f"bundle_{i}.tar")
        with tarfile.open(tar_path, "w") as tf:
            tf.add(gz_path, arcname="payload.gz")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app/doc_stack
