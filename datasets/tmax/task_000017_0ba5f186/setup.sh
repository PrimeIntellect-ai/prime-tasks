#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy requests

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/real_sequences.fasta
>seq1
GATTACAATGCGTGCGCGCGCTACGCAAAAA
>seq2
ATGCGTATATTACGCAGGG
>seq3
CCCCATGCGTGCATGCATTACGCATTTT
>seq4
ATGCGTCGACGTACTACGCA
>seq5
NO_PRIMERS_HERE
>seq6
ATGCGTGGGGGGGGTACGCA
>seq7
ATGCGTTTTTTTTTTACGCA
EOF

    cat << 'EOF' > /home/user/server.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/synthetic':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            data = [
                {"sequence": "GCGC"},
                {"sequence": "ATAT"},
                {"sequence": "GCAT"},
                {"sequence": "GGCC"},
                {"sequence": "AAAA"}
            ]
            self.wfile.write(json.dumps(data).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8080), RequestHandler)
    server.serve_forever()
EOF

    chmod +x /home/user/server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
