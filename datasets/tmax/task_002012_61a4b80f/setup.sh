#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/mini_http_framework

    cat << 'EOF' > /app/mini_http_framework/__init__.py
EOF

    cat << 'EOF' > /app/mini_http_framework/parser.py
def extract_filename(content_disposition_header):
    parts = content_disposition_header.split(' ')
    for part in parts:
        if part.startswith('filename='):
            return part.split('=')[1].strip('"')
    return None
EOF

    cat << 'EOF' > /app/mini_http_framework/server.py
import socket, threading

class MiniHTTPServer:
    def __init__(self, host, port, handler):
        self.host = host
        self.port = port
        self.handler = handler
    def start(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((self.host, self.port))
        s.listen(5)
        threading.Thread(target=self._accept, args=(s,), daemon=True).start()
    def _accept(self, s):
        while True:
            conn, addr = s.accept()
            threading.Thread(target=self._handle, args=(conn,)).start()
    def _handle(self, conn):
        try:
            data = conn.recv(4096).decode('utf-8', errors='ignore')
            if not data: return
            lines = data.split('\r\n')
            req_line = lines[0]
            method, path, _ = req_line.split(' ')
            headers = {}
            i = 1
            while i < len(lines) and lines[i]:
                if ': ' in lines[i]:
                    k, v = lines[i].split(': ', 1)
                    headers[k] = v
                i += 1
            body = data.split('\r\n\r\n', 1)[1] if '\r\n\r\n' in data else ""
            res = self.handler(method, path, headers, body)
            conn.sendall(res.encode('utf-8'))
        except Exception as e:
            conn.sendall(b"HTTP/1.1 500 Internal Server Error\r\n\r\n")
        finally:
            conn.close()
EOF

    cat << 'EOF' > /app/artifact_server.py
import os, sys, socket, threading, urllib.parse
from mini_http_framework.server import MiniHTTPServer
from mini_http_framework.parser import extract_filename

STORE_PATH = os.environ.get("ARTIFACT_STORE_PATH", "/app/artifacts")

def admin_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8081))
    s.listen(5)
    while True:
        conn, _ = s.accept()
        data = conn.recv(1024)
        if b'PING' in data:
            conn.sendall(b'PONG\n')
        conn.close()

def http_handler(method, path, headers, body):
    path = urllib.parse.unquote(path)
    auth = headers.get('Authorization', '')
    if auth != 'Bearer dev-token-123':
        return "HTTP/1.1 401 Unauthorized\r\n\r\n"
    if method == 'POST' and path == '/upload':
        cd = headers.get('Content-Disposition', '')
        if not cd:
            for line in body.split('\n'):
                if 'Content-Disposition:' in line:
                    cd = line.split(':', 1)[1].strip()
                    break
        filename = extract_filename(cd)
        if not filename:
            raise Exception("No filename")
        filepath = os.path.join(STORE_PATH, filename)
        with open(filepath, 'w') as f:
            f.write("dummy content")
        return "HTTP/1.1 200 OK\r\n\r\n"
    elif method == 'GET' and path.startswith('/artifact/'):
        filename = path.split('/artifact/')[1]
        filepath = os.path.join(STORE_PATH, filename)
        if os.path.exists(filepath):
            return "HTTP/1.1 200 OK\r\n\r\n"
        return "HTTP/1.1 404 Not Found\r\n\r\n"
    return "HTTP/1.1 404 Not Found\r\n\r\n"

if __name__ == '__main__':
    test_file = os.path.join(STORE_PATH, '.test')
    try:
        with open(test_file, 'w') as f:
            f.write('test')
    except Exception as e:
        print(f"Startup failed: {e}")
        sys.exit(1)
    threading.Thread(target=admin_server, daemon=True).start()
    server = MiniHTTPServer('127.0.0.1', 8080, http_handler)
    server.start()
    import time
    while True:
        time.sleep(1)
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
export ARTIFACT_STORE_PATH="/app/artifacts"
touch /app/artifacts  # BUG: Creates a file instead of a directory
python3 /app/artifact_server.py
EOF

    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
