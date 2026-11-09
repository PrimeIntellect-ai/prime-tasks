#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nodejs strace curl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/services
cd /home/user/services

# Create status file
echo "OK" > status.txt

# Create backend.py
cat << 'EOF' > backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys

open_files = []

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            f = open('/home/user/services/status.txt', 'r')
            open_files.append(f) # LEAK
            data = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": data.strip()}).encode())
        except Exception as e:
            sys.stderr.write(f"Error handling request: {e}\n")
            sys.exit(1) # Crash the server on error

if __name__ == '__main__':
    sys.stdout.write("Backend started\n")
    sys.stdout.flush()
    server = HTTPServer(('127.0.0.1', 8081), RequestHandler)
    server.serve_forever()
EOF

# Create frontend.js
cat << 'EOF' > frontend.js
const http = require('http');

const server = http.createServer((req, res) => {
    http.get('http://127.0.0.1:8081', (backendRes) => {
        let data = '';
        backendRes.on('data', (chunk) => { data += chunk; });
        backendRes.on('end', () => {
            res.writeHead(backendRes.statusCode, { 'Content-Type': 'application/json' });
            res.end(data);
        });
    }).on('error', (err) => {
        console.error(`Backend connection error: ${err.message}`);
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('502 Bad Gateway');
    });
});

server.listen(8080, '127.0.0.1', () => {
    console.log('Frontend listening on port 8080');
});
EOF

# Create start.sh
cat << 'EOF' > start.sh
#!/bin/bash
cd /home/user/services

# Start frontend
node frontend.js > frontend.log 2>&1 &
FRONTEND_PID=$!

# Start backend loop
(
  while true; do
    python3 backend.py >> backend.log 2>&1
    echo "Backend crashed, restarting..." >> backend.log
    sleep 1
  done
) &
BACKEND_LOOP_PID=$!

echo "Services started."
EOF
chmod +x start.sh

chown -R user:user /home/user/services
chmod -R 777 /home/user
