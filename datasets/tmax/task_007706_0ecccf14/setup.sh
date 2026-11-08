#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl wget procps
    pip3 install pytest

    mkdir -p /home/user/ca-trust
    mkdir -p /home/user/server
    cd /home/user/server

    # Generate a trusted Root CA
    openssl req -x509 -newkey rsa:2048 -keyout root.key -out /home/user/ca-trust/root.crt -days 365 -nodes -subj "/C=US/ST=Test/L=Test/O=Trusted/CN=Trusted Root CA"

    # Generate a ROGUE Root CA (to simulate the compromise)
    openssl req -x509 -newkey rsa:2048 -keyout rogue.key -out rogue.crt -days 365 -nodes -subj "/C=US/ST=Test/L=Test/O=Rogue/CN=Rogue Root CA"

    # Generate server certificate signed by the ROGUE CA
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/C=US/ST=Test/L=Test/O=Server/CN=127.0.0.1"
    openssl x509 -req -in server.csr -CA rogue.crt -CAkey rogue.key -CAcreateserial -out server.crt -days 365

    # Create a manifest with dummy hashes
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  update-1.0.bin" > /home/user/manifest.sha256
    echo "8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92  update-1.1.bin" >> /home/user/manifest.sha256

    # Create a compromised payload
    echo "malicious_payload_data_here" > update.bin

    # Write a simple Python HTTPS server
    cat << 'EOF' > server.py
from http.server import HTTPServer, SimpleHTTPRequestHandler
import ssl

class MaliciousHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Set-Cookie', 'X-Incident-Token=EXFIL_9938_ALPHA; Path=/; Secure; HttpOnly')
        super().end_headers()

httpd = HTTPServer(('127.0.0.1', 8443), MaliciousHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile="server.crt", keyfile="server.key")
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true

    # Ensure the server starts automatically when a shell is spawned
    echo 'if ! pgrep -f "python3 /home/user/server/server.py" > /dev/null; then' >> /etc/bash.bashrc
    echo '  (cd /home/user/server && python3 server.py >/dev/null 2>&1 &)' >> /etc/bash.bashrc
    echo '  sleep 1' >> /etc/bash.bashrc
    echo 'fi' >> /etc/bash.bashrc

    chown -R user:user /home/user
    chmod -R 777 /home/user
