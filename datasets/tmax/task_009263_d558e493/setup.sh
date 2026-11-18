#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/infra/logs

    cat << 'EOF' > /home/user/infra/api.py
import http.server
import socketserver

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 8080), HealthHandler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/infra/config.json
{"target_port": 9090, "log_path": "logs/health.log"}
EOF

    cat << 'EOF' > /home/user/infra/run_monitor.sh
#!/bin/bash
# Simulate cron environment
export PATH=/usr/bin:/bin
unset HOME
cd /
python3 /home/user/infra/monitor.py
EOF

    chmod +x /home/user/infra/run_monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
