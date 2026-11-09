#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 imagemagick
    pip3 install pytest

    mkdir -p /app/data

    # Generate the ticket screenshot
    convert -size 800x200 xc:white -fill black -pointsize 24 -draw "text 10,50 'The new master key is API_KEY=X88-912-SYS-AUTH. Do not lose this.'" /app/ticket_screenshot.png

    # Create the database and leave the WAL file by hard-exiting
    python3 -c "
import sqlite3, os
conn = sqlite3.connect('/app/data/metrics.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE uptime (hostname TEXT, uptime_percentage REAL)')
conn.execute(\"INSERT INTO uptime VALUES ('db-node-01', 99.98)\")
conn.execute(\"INSERT INTO uptime VALUES ('cache-node-02', 99.50)\")
conn.commit()
os._exit(0)
"

    # Corrupt the DB header
    dd if=/dev/zero of=/app/data/metrics.db bs=16 count=1 conv=notrunc
    mv /app/data/metrics.db /app/data/metrics.db.corrupt

    # Create the API server script
    cat << 'EOF' > /app/api_server.py
import sqlite3
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

API_KEY = os.environ.get("API_KEY", "MISSING")
DB_PATH = "/app/data/metrics_recovered.db"
request_history = []

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global request_history
        request_history.append(self.path)

        # Intermittent bug: crashes on the 4th request due to accessing out of bounds
        if len(request_history) == 4:
            bug_trigger = request_history[5] # IndexError

        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            return

        if self.path.startswith('/metrics/'):
            auth_header = self.headers.get('Authorization')
            if auth_header != f"Bearer {API_KEY}":
                self.send_response(401)
                self.end_headers()
                return

            hostname = self.path.split('/')[-1]
            try:
                conn = sqlite3.connect(DB_PATH)
                c = conn.cursor()
                c.execute("SELECT uptime_percentage FROM uptime WHERE hostname=?", (hostname,))
                row = c.fetchone()
                conn.close()
                if row:
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"hostname": hostname, "uptime": row[0]}).encode())
                else:
                    self.send_response(404)
                    self.end_headers()
            except Exception as e:
                self.send_response(500)
                self.end_headers()
            return

        self.send_response(404)
        self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), MetricsHandler)
    print("Starting server on port 8080...")
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
