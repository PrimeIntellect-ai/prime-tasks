#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cmake libcurl4-openssl-dev git tar
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create cJSON tarball
    git clone https://github.com/DaveGamble/cJSON.git /tmp/cJSON_src
    tar -czf /home/user/cJSON.tar.gz -C /tmp cJSON_src
    rm -rf /tmp/cJSON_src

    # Create the python mock server
    cat << 'EOF' > /home/user/mock_server.py
import http.server
import json
import socketserver

class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/telemetry':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                measurements = data.get('measurements', [])
                # Deterministic processing time based on payload
                time_ms = len(measurements) * 5

                response = {"status": "success", "processing_time_ms": time_ms}

                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode('utf-8'))
            except:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass # Suppress logging

PORT = 9090
Handler = MockHandler
httpd = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
httpd.serve_forever()
EOF

    chmod +x /home/user/mock_server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
