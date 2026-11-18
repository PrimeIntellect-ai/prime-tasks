#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/logs
    mkdir -p /home/user/.config/systemd/user/

    cat << 'EOF' > /home/user/app/log_sink.py
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 9000))
s.listen(1)
with open('/home/user/app/logs/server.log', 'a') as f:
    f.write("Log sink started\n")
while True:
    conn, addr = s.accept()
    data = conn.recv(1024)
    if data:
        with open('/home/user/app/logs/server.log', 'a') as f:
            f.write(data.decode())
    conn.close()
EOF
    chmod +x /home/user/app/log_sink.py

    cat << 'EOF' > /home/user/app/web_backend.py
import socket, time, sys
from http.server import HTTPServer, BaseHTTPRequestHandler

# Simulating dependency on log sink at startup
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 9000))
    s.sendall(b"Backend started\n")
    s.close()
except ConnectionRefusedError:
    sys.exit(1)

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Hello from backend")

httpd = HTTPServer(('127.0.0.1', 8080), SimpleHandler)
httpd.serve_forever()
EOF
    chmod +x /home/user/app/web_backend.py

    cat << 'EOF' > /home/user/.config/systemd/user/log-sink.service
[Unit]
Description=Log Sink

[Service]
ExecStart=/usr/bin/python3 /home/user/app/log_sink.py
Restart=on-failure
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/web-backend.service
[Unit]
Description=Web Backend

[Service]
ExecStart=/usr/bin/python3 /home/user/app/web_backend.py
Restart=on-failure
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
