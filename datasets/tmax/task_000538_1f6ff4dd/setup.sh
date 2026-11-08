#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx cron systemd
    pip3 install pytest gunicorn

    mkdir -p /app/backend-api-2.1

    cat << 'EOF' > /app/backend-api-2.1/app.py
def app(environ, start_response):
    if environ.get('PATH_INFO', '') == '/ping':
        start_response('200 OK', [('Content-Type', 'text/plain')])
        return [b'pong']
    start_response('404 Not Found', [('Content-Type', 'text/plain')])
    return [b'not found']
EOF

    cat << 'EOF' > /app/backend-api-2.1/gunicorn_conf.py
import os
bind = "/tmp/broken_deploy.sock"
workers = 2
EOF

    cat << 'EOF' > /app/verifier.py
#!/usr/bin/env python3
import urllib.request
import concurrent.futures

def fetch():
    try:
        res = urllib.request.urlopen("http://127.0.0.1:8080/ping", timeout=2)
        return 1 if res.getcode() == 200 else 0
    except Exception:
        return 0

with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    results = list(executor.map(lambda _: fetch(), range(100)))

success_rate = sum(results) / len(results)
print(f"success_rate={success_rate}")
EOF
    chmod +x /app/verifier.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
