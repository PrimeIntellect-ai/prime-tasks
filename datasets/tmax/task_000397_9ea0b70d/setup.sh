#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd openssl
    pip3 install pytest

    mkdir -p /app/certs
    cd /app/certs
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=CustomCA"
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/CN=localhost"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
    cp ca.crt intermediate.crt

    touch /app/incident.mp4

    cat << 'EOF' > /app/access.log
192.168.1.105 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
192.168.1.105 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
10.0.0.42 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
10.0.0.42 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
172.16.5.99 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
172.16.5.99 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
198.51.100.23 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
198.51.100.23 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
203.0.113.8 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
203.0.113.8 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
192.0.2.55 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
192.0.2.55 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
10.1.1.14 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
10.1.1.14 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
172.18.9.200 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
172.18.9.200 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
198.51.100.77 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
198.51.100.77 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
203.0.113.101 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
203.0.113.101 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
192.168.2.33 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
192.168.2.33 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
10.0.5.5 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
10.0.5.5 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
172.20.0.12 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
172.20.0.12 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
198.51.100.150 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
198.51.100.150 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
203.0.113.210 - - [10/Oct/2023:13:55:36 -0700] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -
203.0.113.210 - - [10/Oct/2023:13:55:37 -0700] "GET /api HTTP/1.1" 200 - "Authorization: Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
EOF

    cat << 'EOF' > /app/server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl
import base64
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/evidence':
            auth = self.headers.get('Authorization')
            if auth and auth.startswith('Bearer '):
                token = auth.split(' ')[1]
                try:
                    parts = token.split('.')
                    if len(parts) == 3 and not parts[2]:
                        hdr = json.loads(base64.urlsafe_b64decode(parts[0] + '==').decode())
                        pld = json.loads(base64.urlsafe_b64decode(parts[1] + '==').decode())
                        if hdr.get('alg') == 'none' and pld.get('user') == 'admin':
                            self.send_response(200)
                            self.end_headers()
                            self.wfile.write(b'FLAG{jwt_alg_none_bypassed_successfully}')
                            return
                except:
                    pass
        self.send_response(403)
        self.end_headers()

httpd = HTTPServer(('127.0.0.1', 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/app/certs/server.crt', keyfile='/app/certs/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
