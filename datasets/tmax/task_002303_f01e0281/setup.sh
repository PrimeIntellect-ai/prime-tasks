#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        openssh-server \
        openssh-client \
        sudo \
        git \
        gcc \
        libc6-dev \
        curl

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup sudo for user
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Setup SSH
    mkdir -p /var/run/sshd
    # Allow local ssh connections
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

    # Create app directories
    mkdir -p /app/bin

    # Create startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 -c "
import http.server, urllib.request, threading
class DB(http.server.BaseHTTPRequestHandler):
    def do_GET(self): self.send_response(200); self.end_headers(); self.wfile.write(b'DB_OK')
class Backend(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            r = urllib.request.urlopen('http://127.0.0.1:8001/', timeout=1).read()
            self.send_response(200); self.end_headers(); self.wfile.write(b'Backend->'+r)
        except Exception:
            self.send_response(500); self.end_headers()
class Frontend(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            r = urllib.request.urlopen('http://127.0.0.1:8002/', timeout=1).read()
            self.send_response(200); self.end_headers(); self.wfile.write(b'Frontend->'+r)
        except Exception:
            self.send_response(500); self.end_headers()
def run(c, p): http.server.HTTPServer(('127.0.0.1', p), c).serve_forever()
threading.Thread(target=run, args=(DB, 9001), daemon=True).start()
threading.Thread(target=run, args=(Backend, 9002), daemon=True).start()
run(Frontend, 9003)
" &
EOF
    chmod +x /app/start_services.sh

    # Create historical log
    cat << 'EOF' > /app/historical.log
[2023-10-12T10:00:00] txid=A1B2C3 status=200 time=45ms
[2023-10-12T10:00:01] txid=D4E5F6 status=200 time=600ms
[2023-10-12T10:00:02] txid=G7H8I9 status=200 time=501ms
[2023-10-12T10:00:03] txid=J0K1L2 status=200 time=500ms
EOF

    # Set permissions
    chown -R user:user /app
    chmod -R 777 /home/user
