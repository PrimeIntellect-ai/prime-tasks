#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data
    echo "sensor_1: 42" > /home/user/sensor_data/readings.txt

    cat << 'EOF' > /home/user/mock_device_cli.py
#!/usr/bin/env python3
import sys
import json
import time

def main():
    dev_id = input("Enter Device ID: ").strip()
    telemetry = input("Enable remote telemetry? (Y/N): ").strip()
    port = input("Enter service port: ").strip()

    if dev_id == "EDGE-404" and telemetry == "Y" and port == "8080":
        with open("/home/user/config.json", "w") as f:
            json.dump({"device_id": dev_id, "telemetry": True, "port": int(port)}, f)
        print("Configuration saved.")
        sys.exit(0)
    else:
        print("Invalid configuration.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/mock_device_cli.py

    cat << 'EOF' > /home/user/edge_service.py
#!/usr/bin/env python3
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

try:
    with open("/home/user/config.json", "r") as f:
        config = json.load(f)
        port = config.get("port", 8080)
except Exception:
    port = 8080

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"OK-EDGE-ACTIVE")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(('127.0.0.1', port), HealthHandler)
    server.serve_forever()
EOF
    chmod +x /home/user/edge_service.py

    # Create dummy pid file so it exists before startscript runs
    echo "99999" > /home/user/dummy_pid.txt

    chmod -R 777 /home/user
