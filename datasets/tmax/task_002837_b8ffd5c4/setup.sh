#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx acl curl tar
    pip3 install pytest pytz

    mkdir -p /home/user/service/public
    mkdir -p /home/user/legacy_data
    mkdir -p /home/user/service/logs

    echo "data1" > /home/user/legacy_data/file1.txt
    echo "data2" > /home/user/legacy_data/file2.txt

    cat << 'EOF' > /home/user/events.log
2023-10-01T12:00:00Z
2023-12-25T17:30:00Z
2024-03-10T06:15:00Z
EOF

    cat << 'EOF' > /home/user/service/app.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import socketserver
import os
import socket
import sys

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Success")

socket_path = sys.argv[1] if len(sys.argv) > 1 else "/home/user/service/wrong.sock"

if os.path.exists(socket_path):
    os.remove(socket_path)

server = socketserver.UnixStreamServer(socket_path, Handler)
server.serve_forever()
EOF

    cat << 'EOF' > /home/user/service/nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/home/user/service/app.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/service/start.sh
#!/bin/bash
cd /home/user/service

stop() {
    if [ -f nginx.pid ]; then
        kill $(cat nginx.pid) 2>/dev/null
        rm nginx.pid
    fi
    if [ -f app.pid ]; then
        kill $(cat app.pid) 2>/dev/null
        rm app.pid
    fi
}

start() {
    python3 app.py /home/user/service/wrong.sock &
    echo $! > app.pid
    nginx -c /home/user/service/nginx.conf -g "pid /home/user/service/nginx.pid; daemon off;" &
    echo $! > nginx.pid
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
EOF
    chmod +x /home/user/service/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
