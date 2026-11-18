#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas requests

    mkdir -p /home/user/data
    mkdir -p /home/user/api

    cat << 'EOF' > /home/user/data/sensors.csv
sensor_id,reading_1
1,10.0
,20.0
3,30.0
4,40.0
EOF

    cat << 'EOF' > /home/user/api/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = [
                {"id": 1, "reading_2": 5.0, "trials": 10, "successes": 6},
                {"id": 3, "reading_2": 15.0, "trials": 20, "successes": 15},
                {"id": 5, "reading_2": 25.0, "trials": 30, "successes": 20}
            ]
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), SimpleHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
