#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat procps psmisc curl lsof
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/target_app.py
import http.server
import socketserver
import time
import math

PORT = 9090
dummy_memory_hog = []

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/compute':
            # Simulate CPU and Memory usage
            global dummy_memory_hog
            dummy_memory_hog.append(" " * 1024 * 1024) # Allocate ~1MB per request
            start = time.time()
            # Spin CPU briefly
            for _ in range(500000):
                math.sqrt(12345.6789)
            time.sleep(0.05) # simulate some I/O delay

            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Computation complete\n")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    chmod +x /home/user/target_app.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
