#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask pandas

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/tracking_server.py
from flask import Flask, request
import os
import subprocess
import tempfile

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file", 400
    file = request.files['file']
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, 'wb') as f:
        file.save(f)

    val_script = os.environ.get("VALIDATOR_SCRIPT")
    if not val_script:
        return "VALIDATOR_SCRIPT not set", 500

    res = subprocess.run(["python3", val_script, path])
    os.remove(path)
    if res.returncode == 0:
        return "OK", 200
    else:
        return "Bad Request", 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

for i in range(50):
    with open(f'/app/corpora/clean/clean_{i}.csv', 'w') as f:
        f.write("epoch,loss,accuracy\n")
        for e in range(5):
            loss = round(random.uniform(0.1, 1.0), 4)
            acc = round(random.uniform(0.5, 1.0), 4)
            f.write(f"{e},{loss},{acc}\n")

for i in range(50):
    with open(f'/app/corpora/evil/evil_{i}.csv', 'w') as f:
        f.write("epoch,loss,accuracy\n")
        for e in range(5):
            loss = round(random.uniform(0.1, 1.0), 4)
            acc = round(random.uniform(0.5, 1.0), 4)
            if i % 4 == 0:
                f.write(f"{e},{-0.5},{acc}\n")
            elif i % 4 == 1:
                f.write(f"{e},{loss},1.5\n")
            elif i % 4 == 2:
                f.write(f"foo,{loss},{acc}\n")
            else:
                f.write(f"{e},{loss},\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
