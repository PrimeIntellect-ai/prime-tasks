#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx git supervisor
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx
    mkdir -p /home/user/logs
    touch /home/user/logs/health.log

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/nginx/access.log;
    error_log /home/user/nginx/error.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 127.0.0.1:8080;
        location / {
            return 404;
        }
    }
}
EOF

    # Create Backend
    cat << 'EOF' > /home/user/backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()
HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    # Create Healthchecker
    cat << 'EOF' > /home/user/healthchecker.py
import time, urllib.request, datetime
while True:
    try:
        start = time.time()
        resp = urllib.request.urlopen('http://127.0.0.1:8080/ping', timeout=1)
        if resp.getcode() == 200:
            latency = int((time.time() - start) * 1000)
            status = 'UP'
        else:
            latency = -1
            status = 'DOWN'
    except Exception:
        latency = -1
        status = 'DOWN'
    with open('/home/user/logs/health.log', 'a') as f:
        f.write(f"{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | {status} | {latency}\n")
    time.sleep(1)
EOF

    # Git setup
    su - user -c '
    git init --bare /home/user/nginx.git
    git clone /home/user/nginx.git /home/user/nginx-repo
    cp /home/user/nginx/nginx.conf /home/user/nginx-repo/
    cd /home/user/nginx-repo
    git config user.email "sre@example.com"
    git config user.name "SRE"
    git add nginx.conf
    git commit -m "Initial nginx config"
    git push origin master
    '

    # Supervisor setup
    cat << 'EOF' > /etc/supervisor/conf.d/services.conf
[program:nginx]
command=/usr/sbin/nginx -c /home/user/nginx/nginx.conf -g "daemon off;"
user=user
autostart=true
autorestart=true

[program:backend]
command=python3 /home/user/backend.py
user=user
autostart=true
autorestart=true

[program:healthchecker]
command=python3 /home/user/healthchecker.py
user=user
autostart=true
autorestart=true
EOF

    # Oracle parser
    mkdir -p /app
    cat << 'EOF' > /app/oracle_parser.py
#!/usr/bin/env python3
import sys
import struct

def main():
    if len(sys.argv) < 2:
        return

    with open(sys.argv[1], 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split('|')
            status = parts[1].strip()
            latency = int(parts[2].strip())

            if status == 'UP':
                b_status = 1
                b_lat = latency
            else:
                b_status = 0
                b_lat = 0

            sys.stdout.buffer.write(struct.pack('<BI', b_status, b_lat))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_parser.py
    ln -s /app/oracle_parser.py /app/oracle_parser

    chown -R user:user /home/user
    chmod -R 777 /home/user
