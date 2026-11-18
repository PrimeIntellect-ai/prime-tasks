#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/math_core.c
double evaluate(double x, double y) {
    return (x * x * x) + (y * y) - (x * y);
}
EOF

    cat << 'EOF' > /home/user/app/server.py
import http.server
import socketserver
import ctypes
from urllib.parse import urlparse, parse_qs

# TODO: Load libmathcore.so and setup FFI
# math_lib = ...

class MathHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # TODO: Route /eval?x=...&y=...
        # Parse the query string, call the C function, and send response
        self.send_response(404)
        self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("", 8080), MathHandler) as httpd:
        httpd.serve_forever()
EOF

    chmod -R 777 /home/user
