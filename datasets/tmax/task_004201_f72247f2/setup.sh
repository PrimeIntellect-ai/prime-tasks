#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/tiny-embed-api
    mkdir -p /app/data

    cat << 'EOF' > /app/tiny-embed-api/server.py
import jsons
from http.server import BaseHTTPRequestHandler, HTTPServer

def get_embedding(text):
    length = len(text)
    v1 = sum(ord(c) for c in text) % 100 / 100.0
    v2 = sum(ord(c) * i for i, c in enumerate(text)) % 100 / 100.0
    v3 = length % 10 / 10.0
    return [v1, v2, v3]

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/embed':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = jsons.loads(post_data)
            text = data.get("text", "")
            embedding = get_embedding(text)
            response = jsons.dumps({"embedding": embedding})

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(response.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def run(server_class=HTTPServer, handler_class=RequestHandler, port=9999):
    server_address = ('127.0.0.1', port)
    httpd = server_class(server_address, handler_class)
    print(f'Starting httpd on {server_address[0]}:{port}...')
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > /app/data/corpus.txt
The quick brown fox
Jumps over the lazy dog
Machine learning is fascinating
Data science requires statistical thinking
Artificial intelligence agents
Building multi-protocol verifiers
Terminal environments for bash
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
