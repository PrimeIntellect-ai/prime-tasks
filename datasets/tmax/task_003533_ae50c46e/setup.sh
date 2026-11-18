#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/temp/client_body
    mkdir -p /home/user/nginx/temp/proxy
    mkdir -p /home/user/nginx/temp/fastcgi
    mkdir -p /home/user/nginx/temp/uwsgi
    mkdir -p /home/user/nginx/temp/scgi
    mkdir -p /home/user/app_data
    mkdir -p /home/user/backend
    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/ {
            # DELIBERATE TYPO FOR TASK: 8099 instead of 8081
            proxy_pass http://127.0.0.1:8099/;
            proxy_set_header Host $host;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backend/server.py
import http.server
import socketserver
import json
import os

PORT = 8081
REPORT_FILE = "/home/user/app_data/report.json"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/report':
            if not os.path.exists(REPORT_FILE):
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Internal Server Error: Report not found.")
                return

            with open(REPORT_FILE, 'r') as f:
                data = json.load(f)

            # Simple check if timezone is UTC string
            if "UTC" not in data.get("generated_at", ""):
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Internal Server Error: Invalid timestamp locale/timezone.")
                return

            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "success", "data": data}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/scripts/generate_report.py
import os
import json
import time

report_dir = os.environ.get("REPORT_DIR", "/tmp/fallback_dir")
os.makedirs(report_dir, exist_ok=True)

# Generate timestamp using system timezone/locale settings
timestamp = time.strftime("%A, %d %B %Y %H:%M:%S %Z", time.localtime())

data = {
    "metrics": {"cpu": 45, "memory": 1024},
    "generated_at": timestamp
}

with open(os.path.join(report_dir, "report.json"), "w") as f:
    json.dump(data, f)
EOF

    cat << 'EOF' > /home/user/scripts/run_job.sh
#!/bin/bash
# A scheduled job wrapper script
# TODO: Fix environment variables so it writes to the correct location and uses UTC timezone / C locale
python3 /home/user/scripts/generate_report.py
EOF

    chmod +x /home/user/scripts/run_job.sh
    chmod -R 777 /home/user
