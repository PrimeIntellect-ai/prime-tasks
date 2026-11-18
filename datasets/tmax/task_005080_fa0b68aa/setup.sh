#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl bc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/doc_writer.py
import time, os
os.makedirs('/home/user/raw_docs', exist_ok=True)
with open('/home/user/raw_docs/active_draft.md', 'w') as f:
    for i in range(1, 9001):
        f.write(f"DOC_LINE: active_{i} This is a line of documentation.\n")
        f.flush()
        time.sleep(0.02)
EOF

    cat << 'EOF' > /app/legacy_archiver.py
import time, os, tarfile
os.makedirs('/home/user/legacy_docs', exist_ok=True)
for i in range(1, 6):
    time.sleep(10)
    filename = f'/home/user/legacy_docs/archive_{i}.tar.gz'
    if i in [2, 4]:
        with open(filename, 'wb') as f:
            f.write(b"corrupted data")
    else:
        with tarfile.open(filename, 'w:gz') as tar:
            with open(f'/tmp/legacy_{i}.md', 'w') as f:
                for j in range(1, 1001):
                    f.write(f"DOC_LINE: legacy_{i}_{j} Legacy doc line.\n")
            tar.add(f'/tmp/legacy_{i}.md', arcname=f'legacy_{i}.md')
EOF

    cat << 'EOF' > /app/indexer_sink.py
import socket, threading, json
from http.server import BaseHTTPRequestHandler, HTTPServer

expected = 9000 + 3 * 1000
received = set()

def tcp_server():
    s = socket.socket()
    s.bind(('0.0.0.0', 9000))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn,)).start()

def handle_client(conn):
    data = b""
    while True:
        chunk = conn.recv(4096)
        if not chunk: break
        data += chunk
        lines = data.split(b'\n')
        for line in lines[:-1]:
            s = line.decode('utf-8', errors='ignore')
            if s.startswith('DOC_LINE: '):
                received.add(s.split()[1])
        data = lines[-1]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/score':
            self.send_response(200)
            self.end_headers()
            score = len(received) / expected
            self.wfile.write(json.dumps({"score": score}).encode())

def http_server():
    server = HTTPServer(('0.0.0.0', 9001), Handler)
    server.serve_forever()

threading.Thread(target=tcp_server, daemon=True).start()
http_server()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/indexer_sink.py &
python3 /app/doc_writer.py &
python3 /app/legacy_archiver.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
