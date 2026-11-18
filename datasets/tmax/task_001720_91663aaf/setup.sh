#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,value
0.0,10.0
1.2,16.0
1.5,-5.0
2.5,22.5
4.0,30.0
5.1,35.5
EOF

    cat << 'EOF' > /home/user/log_server.py
import http.server
import socketserver
import os

PORT = 8123
DIRECTORY = "/home/user"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    chmod +x /home/user/log_server.py

    cat << 'EOF' > /home/user/expected_processed_logs.csv
0,-1.4639
1,-0.8783
2,-0.2928
3,0.2928
4,0.8783
5,1.4639
EOF

    chmod -R 777 /home/user
