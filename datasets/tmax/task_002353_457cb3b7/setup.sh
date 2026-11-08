#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest redis numpy scipy

    mkdir -p /app

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/api_server.py &
python3 /app/worker.py &
sleep 5
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/api_server.py
import http.server
import socketserver
import json
import random

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        services = ["ServiceA", "ServiceB", "ServiceC", "ServiceD", "ServiceE"]
        data = []
        for _ in range(100):
            src = random.choice(services)
            dst = random.choice(services)
            if src != dst:
                latency = random.expovariate(1.0/15.0)
                data.append({"src": src, "dst": dst, "latency": latency})
        self.wfile.write(json.dumps(data).encode())

if __name__ == "__main__":
    with socketserver.TCPServer(("", 8080), Handler) as httpd:
        httpd.serve_forever()
EOF

    cat << 'EOF' > /app/worker.py
import urllib.request
import json
import redis
import time

r = redis.Redis(host='localhost', port=6379, db=0)

while True:
    try:
        req = urllib.request.Request('http://localhost:8080')
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            for item in data:
                r.lpush('raw_traffic', json.dumps(item))
    except Exception:
        pass
    time.sleep(0.5)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
