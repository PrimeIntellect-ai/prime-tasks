#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/static
    mkdir -p /home/user/web_root
    mkdir -p /home/user/client_body /home/user/proxy_temp /home/user/fastcgi_temp /home/user/uwsgi_temp /home/user/scgi_temp

    ln -s /home/user/nonexistent /home/user/web_root/public

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /home/user/error.log;
pid /home/user/nginx.pid;
events { worker_connections 1024; }
http {
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;
    access_log /home/user/access.log;

    server {
        listen 8080;

        location / {
            proxy_pass http://127.0.0.1:9000;
        }

        location /static/ {
            alias /home/user/web_root/public/;
        }
    }
}
EOF

    echo "Hello from static" > /home/user/app/static/index.html

    cat << 'EOF' > /home/user/app/server.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend is alive")

with socketserver.TCPServer(("127.0.0.1", 9001), Handler) as httpd:
    httpd.serve_forever()
EOF

    chmod -R 777 /home/user
