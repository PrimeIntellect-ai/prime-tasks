#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo redis-server
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/mock_api.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/reads':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            # Hardcoded reads for deterministic graph creation
            reads = [
                "ATGCGTA", "TGCGTAC", "CGTACGA", "AAAAAAT", 
                "TTTTTTT", "ATGCGGG", "GGGGGGG", "AAAAAAG",
                "ATGC", "CGTA"
            ]
            self.wfile.write(json.dumps(reads).encode('utf-8'))

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8001), SimpleHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
sudo apt-get update && sudo apt-get install -y redis-server
redis-server --daemonize yes
python3 /home/user/app/mock_api.py &
sleep 2
EOF

    chmod +x /home/user/app/start_services.sh
    chmod -R 777 /home/user
