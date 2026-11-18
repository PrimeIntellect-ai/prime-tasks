#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app /home/user/uploads /opt/verifier

    cat << 'EOF' > /app/upload_server.py
import os
from flask import Flask, request
import redis
import uuid

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

UPLOAD_FOLDER = '/home/user/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return 'No file part', 400
    file = request.files['file']
    if file.filename == '':
        return 'No selected file', 400
    if file:
        filename = str(uuid.uuid4()) + "_" + file.filename
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)
        r.lpush('tasks', filepath)
        return 'File uploaded successfully', 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/worker.py
import os
import redis
import subprocess
import time

r = redis.Redis(host='localhost', port=6379, db=0)
processor = os.environ.get("PROCESSOR_SCRIPT")

while True:
    task = r.brpop('tasks', timeout=1)
    if task:
        _, filepath = task
        filepath = filepath.decode('utf-8')
        if processor:
            subprocess.run(["python3", processor, filepath])
    time.sleep(0.1)
EOF

    cat << 'EOF' > /app/start_worker.sh
#!/bin/bash
python3 /app/worker.py
EOF
    chmod +x /app/start_worker.sh

    cat << 'EOF' > /opt/verifier/oracle_process_artifact.py
import sys
import gzip
import os
import tempfile

def process(filepath):
    with gzip.open(filepath, 'rt', encoding='utf-8') as f:
        content = f.read()

    content = content.replace('__MACRO_REPO_HOST__', 'artifact-repo.internal.srv')

    dir_name = os.path.dirname(filepath)
    fd, temp_path = tempfile.mkstemp(dir=dir_name)
    with os.fdopen(fd, 'wb') as f:
        with gzip.GzipFile(fileobj=f, mode='wb') as gz:
            gz.write(content.encode('utf-8'))

    os.replace(temp_path, filepath)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app /home/user/uploads /opt/verifier
    chmod -R 777 /home/user
