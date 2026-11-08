#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file with a spoken diagnostic code
    espeak -w /app/diag_clean.wav "System failure code bravo niner four"

    # Corrupt the WAV header
    python3 -c '
with open("/app/diag_clean.wav", "rb") as f: data = bytearray(f.read())
data[4:8] = b"\x00\x00\x00\x00"
data[40:44] = b"\x00\x00\x00\x00"
with open("/app/corrupt_diag.wav", "wb") as f: f.write(data)
'
    rm /app/diag_clean.wav

    # Create the service setup script
    cat << 'EOF' > /app/diag_server_source.py
import http.server
import json
import threading
import time

metrics_lock = threading.Lock()
file_lock = threading.Lock()
transcription_count = 0

class DiagHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            # Intentional deadlock setup: acquires metrics_lock then file_lock
            with metrics_lock:
                time.sleep(0.1) # Simulate delay to widen race window
                with file_lock:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps({"count": transcription_count}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        global transcription_count
        if self.path == '/transcribe':
            auth = self.headers.get('Authorization')
            if auth != 'Bearer debug-admin-123':
                self.send_response(401)
                self.end_headers()
                return

            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            filepath = body.get('file')

            # Intentional deadlock setup: acquires file_lock then metrics_lock
            with file_lock:
                time.sleep(0.1) # Simulate I/O
                # (Missing logic to handle corrupted wav and transcribe)
                transcript = "PLACEHOLDER"

                with metrics_lock:
                    transcription_count += 1

            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({"transcript": transcript}).encode())
EOF

    python3 -m py_compile /app/diag_server_source.py
    mv /app/__pycache__/diag_server_source.*.pyc /app/diag_server.pyc
    rm -rf /app/__pycache__
    rm /app/diag_server_source.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
