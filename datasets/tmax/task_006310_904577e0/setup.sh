#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/recon /home/user/certs

    cat << 'EOF' > /home/user/recon/firewall_dump.txt
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 80 -j DROP
-A OUTPUT -p tcp -m tcp --dport 443 -j DROP
-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 8443 -j ACCEPT
COMMIT
EOF

    cd /home/user/certs
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout RootCA.key -out RootCA.crt -subj "/C=US/ST=State/L=City/O=RedTeam/CN=RedTeam_Root_CA"
    openssl req -new -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/C=US/ST=State/L=City/O=RedTeam/CN=c2.internal.thm"
    cat << 'EOF' > extfile.cnf
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = c2.internal.thm
IP.1 = 127.0.0.1
EOF
    openssl x509 -req -in server.csr -CA RootCA.crt -CAkey RootCA.key -CAcreateserial -out server.crt -days 365 -sha256 -extfile extfile.cnf
    rm server.csr extfile.cnf

    cat << 'EOF' > /home/user/c2_server.py
import sys
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler

class C2Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/register' and self.headers.get('Host') == 'c2.internal.thm':
            self.send_response(200)
            self.send_header('Set-Cookie', 'C2-Session-Token=RXhlY3V0ZV9PcGVyYXRpb25fT21lZ2E=')
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"Registered successfully.")
        else:
            self.send_response(403)
            self.end_headers()

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 c2_server.py <PORT>")
        sys.exit(1)
    port = int(sys.argv[1])
    server_address = ('127.0.0.1', port)
    httpd = HTTPServer(server_address, C2Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile="/home/user/certs/server.crt", keyfile="/home/user/certs/server.key")
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    print(f"C2 listening on port {port}...")
    httpd.serve_forever()
EOF

    chmod +x /home/user/c2_server.py
    chmod -R 777 /home/user
