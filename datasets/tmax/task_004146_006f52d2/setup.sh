#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis

    useradd -m -s /bin/bash user || true

    # Create nginx.conf without the correct proxy_pass
    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            root /var/www/html;
        }
        # Add proxy here
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /home/user/search_app.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='dummy', port=1234)

@app.route('/search')
def search():
    q = request.args.get('q')
    # dummy logic
    return jsonify({"results": []})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create oracle binary
    cat << 'EOF' > /opt/doc_archiver_ref
#!/usr/bin/env python3
import sys, json, re

def rle(s):
    def repl(m):
        c = m.group(1)
        l = len(m.group(0))
        if l >= 3:
            return f"~{l}{c}"
        return m.group(0)
    return re.sub(r'([a-zA-Z])\1{2,}', repl, s)

data = []
lines = sys.stdin.read().splitlines()
in_req = False
for line in lines:
    if line.startswith('[REQ_START]'):
        in_req = True
    elif line.startswith('[REQ_END]'):
        in_req = False
    elif in_req:
        try:
            obj = json.loads(line)
            data.append(obj)
        except:
            pass

data.sort(key=lambda x: x.get('endpoint', ''))
csv = "endpoint,status\n" + "\n".join(f"{d.get('endpoint','')},{d.get('status','')}" for d in data)
sys.stdout.write(rle(csv))
EOF
    chmod +x /opt/doc_archiver_ref

    chmod -R 777 /home/user
