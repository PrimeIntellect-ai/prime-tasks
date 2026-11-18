#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest requests

    mkdir -p /home/user/certs
    mkdir -p /home/user/server

    cd /home/user/certs
    openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 -subj "/CN=TestRootCA" -keyout root_ca.key -out root_ca.pem
    openssl req -new -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=127.0.0.1"
    echo "subjectAltName=IP:127.0.0.1" > extfile.cnf
    openssl x509 -req -in server.csr -CA root_ca.pem -CAkey root_ca.key -CAcreateserial -out server.crt -days 365 -sha256 -extfile extfile.cnf
    cat server.crt root_ca.pem > server_chain.pem

    cat << 'EOF' > /home/user/server/server.py
import http.server
import ssl
import json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get('Authorization')
        if auth != 'Bearer AuditToken2024':
            self.send_response(401)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        # Deliberately missing Secure and HttpOnly
        self.send_header('Set-Cookie', 'legacy_session=abc12345; Path=/')
        self.end_headers()

        # Payload: "Compliance_Audit_Success_Data_9921" base64 encoded
        response = {"payload": "Q29tcGxpYW5jZV9BdWRpdF9TdWNjZXNzX0RhdGFfOTkyMQ=="}
        self.wfile.write(json.dumps(response).encode())

httpd = http.server.HTTPServer(('127.0.0.1', 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/home/user/certs/server_chain.pem', keyfile='/home/user/certs/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/vulnerable_client.py
import requests
import argparse
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--token', required=True, help='Secret API token')
    args = parser.parse_args()

    headers = {'Authorization': f'Bearer {args.token}'}

    # INSECURE: verify=False
    response = requests.get('https://127.0.0.1:8443', headers=headers, verify=False)
    print(response.text)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
