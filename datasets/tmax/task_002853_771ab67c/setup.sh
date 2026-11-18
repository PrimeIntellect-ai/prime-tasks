#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest supervisor

    mkdir -p /home/user/restore_test/logs
    cd /home/user/restore_test

    # 1. supervisord.conf
    cat << 'EOF' > supervisord.conf
[supervisord]
logfile=/home/user/restore_test/logs/supervisord.log
pidfile=/home/user/restore_test/logs/supervisord.pid
nodaemon=false

[program:backend]
command=python3 backend.py
autostart=true
autorestart=true
stdout_logfile=/home/user/restore_test/logs/backend.out
stderr_logfile=/home/user/restore_test/logs/backend.err

[program:proxy]
command=python3 proxy.py
autostart=true
autorestart=true
stdout_logfile=/home/user/restore_test/logs/proxy.out
stderr_logfile=/home/user/restore_test/logs/proxy.err

[program:smtp]
command=python3 smtp.py
autostart=true
autorestart=true
stdout_logfile=/home/user/restore_test/logs/smtp.out
stderr_logfile=/home/user/restore_test/logs/smtp.err

[program:healthcheck]
command=python3 healthcheck.py
autostart=true
autorestart=true
stdout_logfile=/home/user/restore_test/logs/healthcheck.out
stderr_logfile=/home/user/restore_test/logs/healthcheck.err
EOF

    # 2. backend.py
    cat << 'EOF' > backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"PONG")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 9000), BackendHandler).serve_forever()
EOF

    # 3. proxy.py
    cat << 'EOF' > proxy.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request

class ProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # BUG: Silently rejects requests without the specific header
        if self.headers.get('X-Backup-Restore-Test') != 'true':
            self.send_response(403)
            self.end_headers()
            return

        try:
            req = urllib.request.urlopen(f"http://127.0.0.1:9000{self.path}")
            self.send_response(req.getcode())
            self.end_headers()
            self.wfile.write(req.read())
        except Exception:
            self.send_response(502)
            self.end_headers()

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8080), ProxyHandler).serve_forever()
EOF

    # 4. smtp.py
    cat << 'EOF' > smtp.py
import smtpd
import asyncore

class CustomSMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open('/home/user/restore_test/logs/mail.log', 'a') as f:
            f.write(f"To: {rcpttos}\nData: {data.decode('utf-8')}\n---\n")

if __name__ == '__main__':
    server = CustomSMTPServer(('127.0.0.1', 8025), None)
    asyncore.loop()
EOF

    # 5. healthcheck.py
    cat << 'EOF' > healthcheck.py
import urllib.request
import smtplib
import time

def send_alert():
    try:
        # BUG: Port is 25 instead of 8025
        server = smtplib.SMTP('127.0.0.1', 25)
        server.sendmail('healthcheck@localhost', ['admin@localhost'], 'Subject: BACKEND DOWN\n\nProxy returned non-200.')
        server.quit()
    except Exception as e:
        print(f"Failed to send alert: {e}")

while True:
    try:
        req = urllib.request.urlopen('http://127.0.0.1:8080/ping')
        if req.getcode() != 200:
            send_alert()
    except Exception:
        send_alert()
    time.sleep(5)
EOF

    chmod +x *.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
