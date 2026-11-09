#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask requests gunicorn

    mkdir -p /home/user/services
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /opt/verifier/corpora/clean
    mkdir -p /opt/verifier/corpora/evil

    # backend.py
    cat << 'EOF' > /home/user/services/backend.py
import sys
import json
from flask import Flask, request, jsonify
import math

app = Flask(__name__)

def check_dict(d):
    for k, v in d.items():
        if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
            return False
        if isinstance(v, str):
            try:
                v.encode('utf-8')
            except UnicodeEncodeError:
                return False
        if isinstance(v, dict):
            if not check_dict(v): return False
        if isinstance(v, list):
            for item in v:
                if isinstance(item, dict):
                    if not check_dict(item): return False
                elif isinstance(item, float) and (math.isnan(item) or math.isinf(item)):
                    return False
                elif isinstance(item, str):
                    try:
                        item.encode('utf-8')
                    except UnicodeEncodeError:
                        return False
    return True

@app.route('/process', methods=['POST'])
def process():
    data_str = request.get_data(as_text=True)
    try:
        data = json.loads(data_str)
    except Exception:
        return jsonify({"status": "error"}), 400

    if not check_dict(data):
        print("CRASH: Poison pill detected!")
        sys.exit(1)

    return jsonify({"status": "ok"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

    # ingestion.py
    cat << 'EOF' > /home/user/services/ingestion.py
import requests
from flask import Flask, request, Response

app = Flask(__name__)

@app.route('/ingest', methods=['POST'])
def ingest():
    resp = requests.post('http://127.0.0.1:5001/process', data=request.get_data(), headers={'Content-Type': 'application/json'})
    return Response(resp.content, resp.status_code, resp.raw.headers.items())

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # nginx.conf
    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # start_services.sh
    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
nginx -c /home/user/nginx.conf &
python3 /home/user/services/backend.py &
python3 /home/user/services/ingestion.py &
sleep 2
EOF
    chmod +x /home/user/start_services.sh

    # Generate corpora
    cat << 'EOF' > /tmp/gen.py
import os
import json
import random

clean_dir = "/home/user/corpora/clean"
evil_dir = "/home/user/corpora/evil"
clean_v_dir = "/opt/verifier/corpora/clean"
evil_v_dir = "/opt/verifier/corpora/evil"

def write_files(directory, count, is_evil):
    for i in range(count):
        if is_evil:
            choice = random.choice([1, 2, 3, 4])
            if choice == 1:
                content = '{"value": NaN}'
            elif choice == 2:
                content = '{"value": Infinity}'
            elif choice == 3:
                content = '{"value": -Infinity}'
            else:
                content = '{"name": "test\\ud800"}'
        else:
            content = json.dumps({"value": random.random(), "name": "test"})

        with open(os.path.join(directory, f"file_{i}.json"), "w") as f:
            f.write(content)

write_files(clean_dir, 50, False)
write_files(evil_dir, 50, True)
write_files(clean_v_dir, 50, False)
write_files(evil_v_dir, 50, True)
EOF
    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /opt/verifier || true
