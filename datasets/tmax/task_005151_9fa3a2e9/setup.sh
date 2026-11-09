#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scipy

# Create user
useradd -m -s /bin/bash user || true

# Create data directory and files
mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/transactions.csv
user_id,transaction_date,amount
1,2023-01-01,100.50
2,2023-01-02,
3,2023-01-02,250.00
4,2023-01-03,50.25
5,2023-01-04,
EOF

cat << 'EOF' > /home/user/data/users.csv
user_id,age,signup_date
1,25,2022-01-01
2,30,2022-02-01
3,,2022-03-01
4,45,2022-04-01
5,22,2022-05-01
EOF

# Create miniserve package
mkdir -p /app/miniserve-0.1.0/miniserve
cat << 'EOF' > /app/miniserve-0.1.0/setup.py
from setuptools import setup, find_packages

setup(
    name="miniserve",
    version="0.1.0",
    packages=find_packages(),
)
EOF

cat << 'EOF' > /app/miniserve-0.1.0/miniserve/__init__.py
from .server import Miniserve
from .response import JsonResponse
EOF

cat << 'EOF' > /app/miniserve-0.1.0/miniserve/response.py
def JsonResponse(data):
    return json.dumps(data)
EOF

cat << 'EOF' > /app/miniserve-0.1.0/miniserve/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

class Request:
    def __init__(self, headers):
        self.headers = headers

class Miniserve:
    def __init__(self):
        self.routes = {}

    def route(self, path, method="GET"):
        def decorator(func):
            self.routes[(path, method)] = func
            return func
        return decorator

    def run(self, host="0.0.0.0", port=8888):
        routes = self.routes
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.handle_request("GET")

            def handle_request(self, method):
                parsed = urlparse(self.path)
                handler = routes.get((parsed.path, method))
                if handler:
                    try:
                        req = Request(dict(self.headers))
                        res = handler(req)

                        if isinstance(res, tuple):
                            body, status = res
                        else:
                            body, status = res, 200

                        self.send_response(status)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        self.wfile.write(body.encode('utf-8'))
                    except Exception as e:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(str(e).encode('utf-8'))
                else:
                    self.send_response(404)
                    self.end_headers()

        server = HTTPServer((host, port), Handler)
        server.serve_forever()
EOF

chmod -R 777 /app
chmod -R 777 /home/user
