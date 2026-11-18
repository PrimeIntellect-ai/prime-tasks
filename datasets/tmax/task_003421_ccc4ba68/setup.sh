#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/c2_sim

    cat << 'EOF' > /app/c2_sim/start.sh
#!/bin/bash
python3 /app/c2_sim/crypto_node.py &
python3 /app/c2_sim/gateway.py &
EOF

    cat << 'EOF' > /app/c2_sim/crypto_node.py
import socket
import struct
import traceback

def converge_signature(data):
    try:
        # BUG: unpacked as signed integers. Causes negative values.
        # Should be '<IIII'
        vals = struct.unpack('<iiii', data)

        seed = 1
        for v in vals:
            seed = (seed * v) & 0xFFFFFFFFFFFFFFFF

        # Convergence loop
        iterations = 0
        while seed % 10007 != 0:
            if seed < 0:
                raise ValueError("State corrupted: negative seed")
            seed = (seed * 1337 + 1) & 0xFFFFFFFFFFFFFFFF
            iterations += 1
            if iterations > 100000:
                raise TimeoutError("Convergence failed")
        return str(seed).encode()
    except Exception as e:
        # Swallows the traceback
        pass
    return b"ERROR"

def run_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 8081))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        data = conn.recv(16)
        if len(data) == 16:
            res = converge_signature(data)
            conn.send(res)
        conn.close()

if __name__ == '__main__':
    run_server()
EOF

    cat << 'EOF' > /app/c2_sim/gateway.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket
import json

class C2Gateway(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/analyze':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            # BUG: hardcoded wrong port, should be 8081
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.connect(('127.0.0.1', 8085))
                s.send(post_data)
                res = s.recv(1024)
                s.close()

                if res == b"ERROR":
                    self.send_response(500)
                    self.end_headers()
                    return

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "success", "signature": res.decode()}).encode())
            except Exception as e:
                self.send_response(503)
                self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), C2Gateway)
    server.serve_forever()
EOF

    chmod +x /app/c2_sim/start.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
