#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/state_svc.py
import http.server
import socketserver
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"State OK")
with socketserver.TCPServer(("127.0.0.1", 8081), Handler) as httpd:
    httpd.serve_forever()
EOF

cat << 'EOF' > /home/user/deploy_svc.py
import http.server
import socketserver
import urllib.request
import sys

# Startup dependency check
try:
    urllib.request.urlopen("http://127.0.0.1:8081", timeout=2)
except Exception as e:
    print("Dependency State Service not found. Exiting.")
    sys.exit(1)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/deploy':
            with open("/home/user/deploy.log", "w") as f:
                f.write("Deployment successful!\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Deployed")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 8080), Handler) as httpd:
    httpd.serve_forever()
EOF

cat << 'EOF' > /home/user/start.sh
#!/bin/bash
python3 /home/user/deploy_svc.py &
python3 /home/user/state_svc.py &
EOF

git init --bare /home/user/registry.git

cat << 'EOF' > /home/user/registry.git/hooks/post-receive
#!/usr/bin/env python3
import urllib.request
import sys
try:
    urllib.request.urlopen("http://127.0.0.1:8080/deploy", timeout=5)
    print("Hook successfully triggered deploy.")
except Exception as e:
    print("Hook failed to trigger deploy:", e)
    sys.exit(1)
EOF

chown -R user:user /home/user/state_svc.py /home/user/deploy_svc.py /home/user/start.sh /home/user/registry.git

chmod -R 777 /home/user
chmod 644 /home/user/registry.git/hooks/post-receive
