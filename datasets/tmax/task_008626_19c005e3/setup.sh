#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl lsof netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/client_temp /home/user/proxy_temp /home/user/fastcgi_temp /home/user/uwsgi_temp /home/user/scgi_temp

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /home/user/nginx_error.log;
pid /home/user/nginx.pid;
events { worker_connections 1024; }
http {
    client_body_temp_path /home/user/client_temp;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;
    access_log /home/user/nginx_access.log;

    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9090;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/server.py
#!/usr/bin/env python3
import http.server
import socketserver

PORT = 8081
Handler = http.server.SimpleHTTPRequestHandler

class CustomHandler(Handler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend Service Operational\n")

with socketserver.TCPServer(("127.0.0.1", PORT), CustomHandler) as httpd:
    httpd.serve_forever()
EOF

    chmod +x /home/user/app/server.py
    chown -R user:user /home/user
    chmod -R 777 /home/user
