#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr strace tcpdump fonts-dejavu
    pip3 install pytest scapy flask requests

    mkdir -p /app

    # Generate config_spec.png
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -annotate +20+40 "SYSTEM CONFIGURATION\nGateway HTTP Port: 8080\nBackend TCP Port: 9090\nModulus Constant: 104729" /app/config_spec.png

    # Generate traffic.pcap
    python3 -c "
from scapy.all import *
ip = IP(src='127.0.0.1', dst='127.0.0.1')
syn = TCP(sport=12345, dport=9090, flags='S', seq=100)
syn_ack = TCP(sport=9090, dport=12345, flags='SA', seq=200, ack=101)
ack = TCP(sport=12345, dport=9090, flags='A', seq=101, ack=201)
req = TCP(sport=12345, dport=9090, flags='PA', seq=101, ack=201) / b'\x05\x00\x00\x00\x00\x00\x00\x00'
resp = TCP(sport=9090, dport=12345, flags='PA', seq=201, ack=109) / b'\x19\x00\x00\x00\x00\x00\x00\x00'
wrpcap('/app/traffic.pcap', [ip/syn, ip/syn_ack, ip/ack, ip/req, ip/resp])
"

    # Create gateway.py
    cat << 'EOF' > /app/gateway.py
import socket
import struct
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        query_components = parse_qs(urlparse(self.path).query)
        if 'val' in query_components:
            val = int(query_components['val'][0])
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(('127.0.0.1', 9000))
            s.send(struct.pack('<q', val))
            data = s.recv(8)
            s.close()
            res = struct.unpack('<q', data)[0]
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'result': res}).encode())
        else:
            self.send_response(400)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8000), RequestHandler)
    server.serve_forever()
EOF

    # Create backend.py
    cat << 'EOF' > /app/backend.py
import socket
import struct
import os

MODULUS = 1000 # Incorrect, needs to be updated from image
PORT = 9000    # Incorrect, needs to be updated from image

def compute(val):
    # THE BUG: Reads 1 byte at a time from /dev/random (blocking) 1024 times instead of /dev/urandom
    padding = b''
    for _ in range(1024):
        with open('/dev/random', 'rb') as f:
            padding += f.read(1)
    return (val**2) % MODULUS

def run():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', PORT))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        data = conn.recv(8)
        if len(data) == 8:
            val = struct.unpack('<q', data)[0]
            res = compute(val)
            conn.send(struct.pack('<q', res))
        conn.close()

if __name__ == '__main__':
    run()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
