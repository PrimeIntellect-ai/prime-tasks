#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_api.py
import sys
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/data':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            data = {"status": "success", "data": {"items": [1, 2, 3, 4, 5], "metadata": "legacy"}}
            self.wfile.write(json.dumps(data).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('127.0.0.1', port), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/new_api.py
import sys
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/data', methods=['GET'])
def get_data():
    from flask import Response
    import json
    data = {"status": "success", "data": {"items": [1, 2, 3, 4, 5], "metadata": "legacy"}}
    return Response(json.dumps(data), mimetype='application/json')

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    app.run(host='127.0.0.1', port=port)
EOF

    chmod -R 777 /home/user
