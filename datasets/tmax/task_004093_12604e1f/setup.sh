#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx expect curl
    pip3 install pytest requests

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/server.py
#!/usr/bin/env python3
import sys
import socket
import os
import http.server
import socketserver

socket_path = "/home/user/app/backend.sock"

# Interactive prompt
sys.stdout.write("Enter startup key: ")
sys.stdout.flush()
key = sys.stdin.readline().strip()

if key != "DeployKey2023!":
    print("Invalid key. Exiting.")
    sys.exit(1)

print("Key accepted. Starting server...")

if os.path.exists(socket_path):
    os.remove(socket_path)

class UnixSocketHttpServer(socketserver.UnixStreamServer):
    def get_request(self):
        request, client_address = self.socket.accept()
        return (request, ["local"])

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

with UnixSocketHttpServer(socket_path, Handler) as httpd:
    # Set permissions so Nginx can read/write to the socket
    os.chmod(socket_path, 0o777)
    httpd.serve_forever()
EOF

    chmod +x /home/user/app/server.py

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;

    upstream backend {
        # DELIBERATE ERROR: Wrong socket name
        server unix:/home/user/app/wrong.sock;
    }

    server {
        listen 8080;
        server_name 127.0.0.1;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
