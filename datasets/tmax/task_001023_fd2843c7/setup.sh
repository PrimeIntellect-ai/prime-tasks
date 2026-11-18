#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest

    mkdir -p /app/webhook-notifier-1.0.0

    cat << 'EOF' > /app/webhook-notifier-1.0.0/server.py
import os
import smtplib
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import datetime

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/deploy':
            # Create backup
            backup_dir = os.environ.get('BACKUP_DIR', '/tmp')
            source_dir = os.environ.get('SOURCE_DIR', '/tmp')
            timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            backup_file = os.path.join(backup_dir, f"backup_{timestamp}.tar.gz")
            subprocess.run(['tar', '-czf', backup_file, source_dir])

            # Send email
            smtp_port = os.environ.get('SMTP_PORT', '8025')
            try:
                server = smtplib.SMTP('127.0.0.1', smtp_port)
                msg = f"Subject: Deploy triggered\n\nBackup created at {backup_file}"
                server.sendmail("webhook@localhost", "admin@localhost", msg)
                server.quit()

                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Success")
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    server = HTTPServer(('127.0.0.1', port), WebhookHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/webhook-notifier-1.0.0/webhook-notifier.service
[Unit]
Description=Webhook Notifier

[Service]
ExecStart=/usr/bin/python3 /app/webhook-notifier-1.0.0/server.py
Environment="SMTP_PORT=8025"
Environment="BACKUP_DIR=/home/user/backups/"
Environment="SOURCE_DIR=/home/user/project.git"
Restart=always

[Install]
WantedBy=default.target
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
