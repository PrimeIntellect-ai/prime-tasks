#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis flask

    mkdir -p /app/docs

    cat << 'EOF' > /app/doc_writer.py
import os
import time
import fcntl
import random
import redis

r = redis.Redis(host='localhost', port=6379, db=0)
encodings = ['iso-8859-1', 'shift_jis', 'utf-16']
docs_dir = '/app/docs'

def write_files():
    for i in range(50):
        filename = f"doc_{i}.txt"
        filepath = os.path.join(docs_dir, filename)
        encoding = random.choice(encodings)
        content = ("This is a repetitive document. " * 1000).encode(encoding)

        with open(filepath, 'wb') as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(content)
            fcntl.flock(f, fcntl.LOCK_UN)

        r.set(f"encoding:{filename}", encoding)
        time.sleep(0.05)

    for i in range(10):
        filename = f"media_{i}.media"
        filepath = os.path.join(docs_dir, filename)
        content = os.urandom(2 * 1024 * 1024)

        with open(filepath, 'wb') as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(content)
            fcntl.flock(f, fcntl.LOCK_UN)
        time.sleep(0.05)

if __name__ == '__main__':
    while True:
        write_files()
        time.sleep(5)
EOF

    cat << 'EOF' > /app/doc_server.py
from flask import Flask
app = Flask(__name__)

@app.route('/')
def status():
    return "OK"

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/doc_server.py &
python3 /app/doc_writer.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
