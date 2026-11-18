#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget coreutils procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/build_manifest.bld
PYTHON|requests|e134621c5040669b7bb6933bb3e31ecbaea2b3c20c02fb367e9f390d40e4ab7d
RUST|serde|f22f281e59273c524e4c29ea76d2036c0a0058b297bcf95da4e8c1050e8200dd
JS|lodash|0000000000000000000000000000000000000000000000000000000000000000
GO|gin|not_real_will_404
EOF

    cat << 'EOF' > /tmp/mock_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import time

last_request_time = 0

class RateLimitedHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global last_request_time
        current_time = time.time()

        if current_time - last_request_time < 1.0:
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"Too Many Requests")
            return

        last_request_time = current_time

        if self.path == "/deps/requests":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"print('requests')\n")
        elif self.path == "/deps/serde":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"fn serde() {}\n")
        elif self.path == "/deps/lodash":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"function lodash() {}\n") # Checksum will fail for this intentionally
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8080), RateLimitedHandler)
    server.serve_forever()
EOF

    echo 'pgrep -f mock_server.py > /dev/null || python3 /tmp/mock_server.py &' >> /etc/bash.bashrc
    echo 'pgrep -f mock_server.py > /dev/null || python3 /tmp/mock_server.py &' >> /etc/profile
    echo 'pgrep -f mock_server.py > /dev/null || python3 /tmp/mock_server.py &' >> /home/user/.bashrc

    chmod -R 777 /home/user
