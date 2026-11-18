#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron curl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/data_initializer.py
import time, json
time.sleep(5)
with open("/home/user/app/shared_data.json", "w") as f:
    json.dump({"status": "ready", "data": [1, 2, 3]}, f)
EOF

    cat << 'EOF' > /home/user/app/backend_api.py
import json, sys, http.server, socketserver
try:
    with open("/home/user/app/shared_data.json", "r") as f:
        data = json.load(f)
except FileNotFoundError:
    sys.exit(1)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 8080), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
python3 /home/user/app/data_initializer.py &
python3 /home/user/app/backend_api.py &
wait
EOF
    chmod +x /home/user/app/start_services.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
