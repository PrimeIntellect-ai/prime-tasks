#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl procps
    pip3 install pytest pexpect

    # Create directories
    mkdir -p /app/data_service-1.2.0/bin

    # Create disk_monitor.py
    cat << 'EOF' > /app/data_service-1.2.0/disk_monitor.py
import shutil

def check_space():
    free_space = shutil.disk_usage('/tmp').free
    if free_space < 500 * 1024**4:
        raise Exception("Not enough disk space")

check_space()
EOF

    # Create server.py
    cat << 'EOF' > /app/data_service-1.2.0/server.py
import disk_monitor
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/data':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "data": "vendored_app_active"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9000), RequestHandler)
    server.serve_forever()
EOF

    # Create start_service.sh
    cat << 'EOF' > /app/data_service-1.2.0/bin/start_service.sh
#!/bin/bash
read -p "Do you want to start the service? (y/n): " answer
if [ "$answer" = "y" ]; then
    python3 /app/data_service-1.2.0/server.py
fi
EOF
    chmod +x /app/data_service-1.2.0/bin/start_service.sh

    # Configure Nginx
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

    # Ensure nginx starts when a shell is opened (to satisfy tests that expect it running)
    echo 'service nginx status >/dev/null || service nginx start >/dev/null 2>&1' >> /etc/bash.bashrc

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
