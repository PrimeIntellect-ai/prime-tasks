#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/health_logs
    mkdir -p /home/user/watcher_dir

    cat << 'EOF' > /home/user/app.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class PingHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'pong')
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(('localhost', 8080), PingHandler).serve_forever()
EOF

    cat << 'EOF' > /home/user/watcher.py
import subprocess
import time
import os

while True:
    # Run with stripped environment and wrong working directory
    subprocess.run(
        ["/bin/bash", "/home/user/health_monitor.sh"],
        env={"PWD": "/home/user/watcher_dir"},
        cwd="/home/user/watcher_dir"
    )
    time.sleep(2)
EOF

    cat << 'EOF' > /home/user/health_monitor.sh
#!/bin/bash
# Intentionally broken: assumes curl is in PATH, uses relative paths
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ping)
echo $code >> status.log
EOF
    chmod +x /home/user/health_monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
