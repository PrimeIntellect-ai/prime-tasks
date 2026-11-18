#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron logrotate procps
pip3 install pytest requests

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/flaky_api.py
import http.server
import socketserver
import time
import os

class FlakyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            if os.path.exists('/home/user/hang.flag'):
                time.sleep(5) # Simulate hang
            if os.path.exists('/home/user/error.flag'):
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Internal Server Error")
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    with socketserver.TCPServer(("127.0.0.1", 8080), FlakyHandler) as httpd:
        httpd.serve_forever()
EOF

chmod +x /home/user/flaky_api.py
chmod -R 777 /home/user
