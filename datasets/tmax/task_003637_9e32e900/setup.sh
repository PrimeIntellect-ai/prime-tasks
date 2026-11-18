#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc curl nmap
pip3 install pytest numpy scipy

mkdir -p /app

# Create the audit server
cat << 'EOF' > /app/audit_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import base64

class AuditHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(401)
            self.send_header('Set-Cookie', 'session=guest; Path=/')
            self.send_header('X-Required-Role', 'admin')
            self.end_headers()
            self.wfile.write(b"Unauthorized. Check headers for requirements.")
        elif self.path == '/logs':
            cookie = self.headers.get('Cookie', '')
            if 'session=admin' in cookie:
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                payload = base64.b64encode(b"REDACT_START:44100,REDACT_END:88200").decode('utf-8')
                self.wfile.write(f"AUDIT_PAYLOAD: {payload}".encode('utf-8'))
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden. Invalid session.")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8042), AuditHandler)
    server.serve_forever()
EOF

# Generate WAV files
cat << 'EOF' > /app/generate_wavs.py
import numpy as np
from scipy.io import wavfile

sr = 44100
duration = 3
data = np.random.randint(-32768, 32767, sr * duration, dtype=np.int16)
wavfile.write('/app/intercept.wav', sr, data)

data_clean = data.copy()
data_clean[44100:88201] = 0
wavfile.write('/app/reference_clean.wav', sr, data_clean)
EOF

python3 /app/generate_wavs.py

# Create user
useradd -m -s /bin/bash user || true

# Ensure server starts on interactive shell if not already running
echo 'pgrep -f audit_server.py > /dev/null || python3 /app/audit_server.py &' >> /home/user/.bashrc

chmod -R 777 /home/user
chmod -R 777 /app
