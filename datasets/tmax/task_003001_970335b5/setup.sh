#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cron
    pip3 install pytest

    # Create the dummy services script
    cat << 'EOF' > /usr/local/bin/dummy_services.py
import http.server
import socketserver
import threading

class Handler8001(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

class Handler8002(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

class Handler8003(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(503)
        self.end_headers()
        self.wfile.write(b"Service Unavailable")

def run_server(port, handler):
    class MyServer(socketserver.TCPServer):
        allow_reuse_address = True
    httpd = MyServer(("127.0.0.1", port), handler)
    httpd.serve_forever()

threading.Thread(target=run_server, args=(8001, Handler8001), daemon=True).start()
threading.Thread(target=run_server, args=(8002, Handler8002), daemon=True).start()
run_server(8003, Handler8003)
EOF

    # Ensure the services start automatically when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-services.sh
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=1)" 2>/dev/null; then
    python3 /usr/local/bin/dummy_services.py >/dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-services.sh

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/webhook
    chmod -R 777 /home/user
