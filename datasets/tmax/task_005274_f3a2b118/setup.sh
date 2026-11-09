#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /app/vendored/py2num/py2num
    mkdir -p /home/user

    # Create setup.py
    cat << 'EOF' > /app/vendored/py2num/setup.py
from setuptools import setup, find_packages
print "Installing py2num..."
setup(
    name="py2num",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    # Create __init__.py
    cat << 'EOF' > /app/vendored/py2num/py2num/__init__.py
from .core import sum_of_squares
EOF

    # Create core.py
    cat << 'EOF' > /app/vendored/py2num/py2num/core.py
def sum_of_squares(n):
    # Intentional py2 syntax
    total = 0
    for i in xrange(1, long(n) + 1):
        total += i * i
    return total
EOF

    # Create server.py
    cat << 'EOF' > /home/user/server.py
import json
import BaseHTTPServer
from py2num import sum_of_squares

# Intentional Memory Leak: Caching all results globally without a bound
HISTORY_CACHE = {}

class RequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/compute':
            auth_header = self.headers.getheader('X-Migration-Auth')
            if auth_header != '99887766':
                self.send_response(401)
                self.end_headers()
                return

            content_length = int(self.headers.getheader('Content-Length', 0))
            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                n = data['n']

                # Leaky caching mechanism
                if n not in HISTORY_CACHE:
                    HISTORY_CACHE[n] = sum_of_squares(n)
                    # Leak: storing a large useless array in memory for every request
                    HISTORY_CACHE[f"{n}_metadata"] = [i for i in range(1000000)]

                response_data = json.dumps({"result": HISTORY_CACHE[n]})
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(response_data)
            except Exception as e:
                self.send_response(400)
                self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8080)
    httpd = BaseHTTPServer.HTTPServer(server_address, RequestHandler)
    httpd.serve_forever()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
