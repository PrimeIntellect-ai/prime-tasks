#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_app

    cat << 'EOF' > /home/user/legacy_app/server.py
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8181
server = HTTPServer(('127.0.0.1', port), HealthHandler)
server.serve_forever()
EOF

    cat << 'EOF' > /home/user/legacy_app/start_service.sh
#!/bin/bash
read -p "Enter Environment (dev/prod): " env
read -p "Enter Service Port [1000-9999]: " port
read -p "Enable verbose logging? (y/n): " verbose

echo "ENV=$env" > /home/user/legacy_app/service.conf
echo "PORT=$port" >> /home/user/legacy_app/service.conf
echo "VERBOSE=$verbose" >> /home/user/legacy_app/service.conf

# Start the python server in the background
nohup python3 /home/user/legacy_app/server.py $port > /dev/null 2>&1 &
echo "Service started."
EOF

    chmod +x /home/user/legacy_app/start_service.sh
    chmod -R 777 /home/user
