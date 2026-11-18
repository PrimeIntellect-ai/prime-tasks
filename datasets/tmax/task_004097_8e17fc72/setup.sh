#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl
pip3 install pytest flask

mkdir -p /home/user/corpora/evil /home/user/corpora/clean /home/user/app

# Evil corpus
cat << 'EOF' > /home/user/corpora/evil/test_evil.jsonl
{"id": "e1", "cmdline": ["aws", "s3", "ls", "AKIAIOSFODNN7EXAMPLE"]}
{"id": "e2", "cmdline": ["myscript", "--password=supersecret"]}
{"id": "e3", "cmdline": ["app", "-s", "mytoken123"]}
{"id": "e4", "cmdline": ["app", "-p", "pass", "--verbose"]}
EOF

# Clean corpus
cat << 'EOF' > /home/user/corpora/clean/test_clean.jsonl
{"id": "c1", "cmdline": ["aws", "s3", "ls", "some-bucket"]}
{"id": "c2", "cmdline": ["myscript", "--password-file=/etc/secrets"]}
{"id": "c3", "cmdline": ["app", "-s", "-v"]}
{"id": "c4", "cmdline": ["app", "-p"]}
{"id": "c5", "cmdline": ["python3", "worker.py", "--notasecret"]}
EOF

# App files
cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request, jsonify
import subprocess

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    secret = data.get('secret', '')
    # Vulnerability: Secret leaked in cmdline
    result = subprocess.run(['python3', 'worker.py', '--secret', secret], capture_output=True, text=True)
    return jsonify({"status": "success", "worker_output": result.stdout.strip()})

if __name__ == '__main__':
    # Vulnerability: Binds to 0.0.0.0
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > /home/user/app/worker.py
import sys
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--secret', help='The secret to process', default='')
args = parser.parse_args()

# Simulate processing
if args.secret:
    print(f"Processed_{args.secret[:4]}***")
else:
    print("No secret provided")
EOF

cat << 'EOF' > /home/user/app/nginx.conf
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

cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
nginx -c /home/user/app/nginx.conf &
python3 /home/user/app/api.py &
sleep 2
EOF
chmod +x /home/user/app/start.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
