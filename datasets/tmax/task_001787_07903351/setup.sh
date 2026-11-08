#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl procps curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/client_certs /home/user/server

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/CN=Test CA"

    # Generate Server cert
    openssl req -newkey rsa:2048 -keyout /home/user/server/server.key -out /home/user/server/server.csr -nodes -subj "/CN=localhost"
    openssl x509 -req -in /home/user/server/server.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/server/server.crt -days 365

    # Generate Client 1 (Self-signed - INVALID)
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/client_certs/client1.key -out /home/user/client_certs/client1.crt -days 365 -nodes -subj "/CN=Client 1"

    # Generate Client 2 (Signed by CA - VALID)
    openssl req -newkey rsa:2048 -keyout /home/user/client_certs/client2.key -out /home/user/client_certs/client2.csr -nodes -subj "/CN=Client 2"
    openssl x509 -req -in /home/user/client_certs/client2.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/client_certs/client2.crt -days 365

    # Generate Client 3 (Signed by a fake CA - INVALID)
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/fake_ca.key -out /tmp/fake_ca.crt -days 365 -nodes -subj "/CN=Fake CA"
    openssl req -newkey rsa:2048 -keyout /home/user/client_certs/client3.key -out /home/user/client_certs/client3.csr -nodes -subj "/CN=Client 3"
    openssl x509 -req -in /home/user/client_certs/client3.csr -CA /tmp/fake_ca.crt -CAkey /tmp/fake_ca.key -CAcreateserial -out /home/user/client_certs/client3.crt -days 365

    # Python server setup
    cat << 'EOF' > /home/user/server/server.py
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
import base64

payload_str = "IP:10.50.200.15;PORT:6666;FLAG:PT_SECURE_8484_ZZ"
encoded_payload = base64.b64encode(payload_str.encode()).decode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/payload':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(encoded_payload.encode())
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('localhost', 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.verify_mode = ssl.CERT_REQUIRED
context.load_verify_locations('/home/user/ca.crt')
context.load_cert_chain(certfile='/home/user/server/server.crt', keyfile='/home/user/server/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    # Add a hook to start the server in bash sessions if not running
    echo 'if ! pgrep -f "python3 /home/user/server/server.py" > /dev/null; then' >> /home/user/.bashrc
    echo '    python3 /home/user/server/server.py &' >> /home/user/.bashrc
    echo '    sleep 1' >> /home/user/.bashrc
    echo 'fi' >> /home/user/.bashrc

    chmod -R 777 /home/user
