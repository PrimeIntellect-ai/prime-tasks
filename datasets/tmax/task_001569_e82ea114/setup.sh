#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/monitor

# Create the mock server script
cat << 'EOF' > /home/user/monitor/mock_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class MockServerRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/good1':
            self.send_response(200)
            self.end_headers()
        elif self.path == '/good2':
            self.send_response(301)
            self.end_headers()
        elif self.path == '/bad':
            self.send_response(500)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

def run():
    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, MockServerRequestHandler)
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

# Create the corrupted endpoints.json (trailing comma)
cat << 'EOF' > /home/user/monitor/endpoints.json
{
  "sites": [
    "http://localhost:8080/good1",
    "http://localhost:8080/good2",
    "http://localhost:8080/bad",
  ]
}
EOF

# Create the buggy monitor script
cat << 'EOF' > /home/user/monitor/uptime_monitor.py
import json
import urllib.request
import urllib.error

def check_sites():
    # Bug 1: Will fail because endpoints.json has a trailing comma (invalid JSON)
    with open('/home/user/monitor/endpoints.json', 'r') as f:
        data = json.load(f)

    results = []
    for url in data['sites']:
        try:
            req = urllib.request.urlopen(url)
            status = req.getcode()
        except urllib.error.HTTPError as e:
            status = e.code
        except Exception:
            status = 0

        # Bug 2: Fails when checking /bad (returns 500)
        assert status in [200, 301], f"AssertionFailed: {url} returned {status}"

        if status in [200, 301]:
            results.append(f"{url} - UP")
        else:
            results.append(f"{url} - DOWN")

    with open('/home/user/monitor/report.txt', 'w') as f:
        f.write('\n'.join(results))

if __name__ == "__main__":
    check_sites()
EOF

chmod -R 777 /home/user
