#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/tmp/wrong.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/webapp.py
import socket
import os
import sys

sock_path = "/home/user/app.sock"
if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

while True:
    conn, _ = server.accept()
    data = conn.recv(1024)
    if data:
        response = b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World!"
        conn.sendall(response)
    conn.close()
EOF

    cat << 'EOF' > /home/user/router_cli.py
import sys
import time

def main():
    sys.stdout.write("Username: ")
    sys.stdout.flush()
    user = sys.stdin.readline().strip()

    sys.stdout.write("Password: ")
    sys.stdout.flush()
    passwd = sys.stdin.readline().strip()

    if user == "admin" and passwd == "secret":
        while True:
            sys.stdout.write("Router> ")
            sys.stdout.flush()
            cmd = sys.stdin.readline().strip()
            if cmd == "enable bgp":
                with open("/home/user/bgp_enabled.log", "w") as f:
                    f.write("BGP is UP\n")
            elif cmd == "exit":
                break
    else:
        print("Login failed")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/fake_fstab
# /etc/fstab
/dev/sda1 / ext4 defaults 1 1
backup_drive /home/user/backups ext4 defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
