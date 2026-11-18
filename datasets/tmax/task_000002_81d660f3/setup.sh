#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/api_server.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"API_OK")

httpd = socketserver.TCPServer(("127.0.0.1", 9001), Handler)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/lb.py
import socket
import sys
import threading

def check_port(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        return True
    except:
        return False

if not check_port(9001) or not check_port(9002):
    print("Backends not available")
    sys.exit(1)

# Simple round robin proxy
backends = [9001, 9002]
current = 0

def handle_client(client_socket):
    global current
    target_port = backends[current]
    current = (current + 1) % len(backends)

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.connect(("127.0.0.1", target_port))

    def forward(src, dst):
        try:
            while True:
                data = src.recv(4096)
                if len(data) == 0:
                    break
                dst.send(data)
        except:
            pass
        finally:
            src.close()
            dst.close()

    threading.Thread(target=forward, args=(client_socket, server_socket)).start()
    threading.Thread(target=forward, args=(server_socket, client_socket)).start()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("127.0.0.1", 9000))
server.listen(5)

while True:
    client_sock, _ = server.accept()
    handle_client(client_sock)
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/api.service
[Unit]
Description=API Server

[Service]
ExecStart=/usr/bin/python3 /home/user/api_server.py
Type=simple
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/tunnel.service
[Unit]
Description=Tunnel Server

[Service]
ExecStart=/usr/bin/python3 /home/user/tunnel.py
Type=simple
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/lb.service
[Unit]
Description=Load Balancer

[Service]
ExecStart=/usr/bin/python3 /home/user/lb.py
Type=simple
EOF

    chown -R user:user /home/user/
    chmod -R 777 /home/user
