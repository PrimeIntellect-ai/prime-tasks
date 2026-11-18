#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd curl gawk
    pip3 install pytest numpy scipy requests

    mkdir -p /app

    cat << 'EOF' > /app/data_emitter.py
import socketserver
import math
import random

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"time,value\n")
        random.seed(42)
        for i in range(1024):
            t = i * 0.01
            val = 5.0 + 3.0 * math.sin(2 * math.pi * 15.0 * t) + random.gauss(0, 1)
            self.wfile.write(f"{t:.2f},{val:.6f}\n".encode())

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer(("127.0.0.1", 9001), Handler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nohup python3 /app/data_emitter.py > /app/emitter.log 2>&1 &
sleep 1
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
