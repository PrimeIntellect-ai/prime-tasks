#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl openssl
pip3 install pytest

mkdir -p /home/user/static_files
echo "<h1>Welcome to the secure app</h1>" > /home/user/static_files/index.html

cat << 'EOF' > /home/user/server.py
import ssl
import http.server
import sys
import os

if len(sys.argv) != 4:
    print("Usage: server.py <port> <cert_file> <key_file>")
    sys.exit(1)

port = int(sys.argv[1])
cert = sys.argv[2]
key = sys.argv[3]

server_address = ('localhost', port)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=cert, keyfile=key)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

print(f"Serving on port {port}...")
httpd.serve_forever()
EOF

cat << 'EOF' > /home/user/manager.sh
#!/bin/bash

ACTION=$1
APP_NAME=$2

if [ "$ACTION" == "start" ]; then
    mkdir -p /home/user/containers/$APP_NAME
    # BUG 1: Bad relative symlink
    ln -sf static_files /home/user/containers/$APP_NAME/www

    cd /home/user/containers/$APP_NAME/www

    # BUG 2: Missing cert paths
    python3 /home/user/server.py 8443 cert.pem key.pem &
    echo $! > ../server.pid
    echo "Started $APP_NAME"
elif [ "$ACTION" == "stop" ]; then
    kill $(cat /home/user/containers/$APP_NAME/server.pid)
fi
EOF

chmod +x /home/user/manager.sh
mkdir -p /home/user/certs

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
