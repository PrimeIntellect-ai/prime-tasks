#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_api.py
# /home/user/mock_api.py
import http.server
import socketserver
import json

PORT = 9090

class MockAPIHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/v1/dependencies':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = [
                {"name": "service_auth", "depends_on": ["service_db", "service_cache"], "config_data": "auth_config_v2"},
                {"name": "service_db", "depends_on": ["service_network"], "config_data": "db_config_v2"},
                {"name": "service_cache", "depends_on": ["service_network"], "config_data": "cache_config_v2"},
                {"name": "service_api", "depends_on": ["service_auth", "service_logic"], "config_data": "api_config_v2"},
                {"name": "service_network", "depends_on": [], "config_data": "network_config_v2"},
                {"name": "service_logic", "depends_on": ["service_db"], "config_data": "logic_config_v2"}
            ]
            self.wfile.write(json.dumps(data).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("", PORT), MockAPIHandler) as httpd:
    httpd.serve_forever()
EOF

    chmod -R 777 /home/user
