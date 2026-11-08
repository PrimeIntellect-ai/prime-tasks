#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssl curl
    pip3 install pytest

    mkdir -p /home/user/nginx/conf
    mkdir -p /home/user/nginx/logs

    cat << 'EOF' > /home/user/mock_passwd
root:x:0:0:root:/root:/bin/bash
bin:x:2:2:bin:/bin:/usr/sbin/nologin
user:x:1000:1000:User:/home/user:/bin/bash
EOF

    cat << 'EOF' > /home/user/backend.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend Application Running!")

httpd = socketserver.TCPServer(("127.0.0.1", 8000), Handler)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/nginx/conf/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /home/user/nginx/certs/server.crt;
        ssl_certificate_key /home/user/nginx/certs/server.key;

        location / {
            # Misconfigured port representing network isolation/bad gateway
            proxy_pass http://127.0.0.1:9999;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
