#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest pexpect requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.certs
    openssl req -new -x509 -keyout /home/user/.certs/server.pem -out /home/user/.certs/server.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=localhost" 2>/dev/null

    cat << 'EOF' > /home/user/mock_server.py
import http.server
import ssl
import json

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy", "uptime": 3600}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

server_address = ('127.0.0.1', 8443)
httpd = http.server.HTTPServer(server_address, HealthHandler)
httpd.socket = ssl.wrap_socket(httpd.socket, certfile='/home/user/.certs/server.pem', server_side=True)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/rollout.sh
#!/bin/bash
read -p "Target environment (dev/staging/prod): " env
if [ "$env" != "staging" ]; then
    echo "Aborting: only staging is supported in this test."
    exit 1
fi
read -p "Confirm staged rollout? [y/N]: " conf
if [ "$conf" != "y" ]; then
    echo "Aborted."
    exit 1
fi

echo "Deploying..."
# Start the web server in the background
nohup python3 /home/user/mock_server.py > /dev/null 2>&1 &
echo $! > /home/user/server.pid
sleep 2
echo "Rollout complete."
EOF

    chmod +x /home/user/rollout.sh
    chown -R user:user /home/user/rollout.sh /home/user/mock_server.py /home/user/.certs
    chmod -R 777 /home/user
