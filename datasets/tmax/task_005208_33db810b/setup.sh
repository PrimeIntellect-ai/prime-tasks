#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/legacy_data
    echo "db_version=1.4.2" > /home/user/legacy_data/config.ini

    cat << 'EOF' > /home/user/legacy_users.csv
admin,admin,admin@corp.com
jdoe,user,jdoe@corp.com
msmith,admin,msmith@corp.com
EOF

    cat << 'EOF' > /home/user/app.py
import http.server
import socketserver
PORT = 8080
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
