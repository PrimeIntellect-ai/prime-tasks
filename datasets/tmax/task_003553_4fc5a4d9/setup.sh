#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl
pip3 install pytest

# Create the broken health check script
mkdir -p /home/user/scripts
cat << 'EOF' > /home/user/scripts/health_check.sh
#!/bin/bash
# Broken health check script
PORT=8008 # TYPO
URL="http://127.0.0.1:${PORT}/ping"

# Fails if directory doesn't exist
echo "Checking $URL" > /home/user/logz/health.log # TYPO IN DIR

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" $URL)

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "STATUS: GOOD" >> /home/user/logz/health.log # WRONG STRING
fi
EOF
chmod +x /home/user/scripts/health_check.sh

# Create the dummy server script
cat << 'EOF' > /usr/local/bin/dummy_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class S(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"pong")
HTTPServer(("127.0.0.1", 8080), S).serve_forever()
EOF

# Start the dummy server in the background whenever a bash shell is opened
echo "nohup python3 /usr/local/bin/dummy_server.py >/dev/null 2>&1 &" >> /etc/bash.bashrc

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
