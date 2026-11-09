#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssl
    pip3 install pytest

    mkdir -p /home/user/forensics_lab
    cd /home/user/forensics_lab

    # Create the encrypted evidence
    echo "EVIDENCE_RECOVERED_C2_IP_10.10.10.55" > clear.txt
    openssl enc -aes-256-cbc -pbkdf2 -k "f0r3ns1cs!" -in clear.txt -out evidence.enc
    rm clear.txt

    # Create Nginx config
    cat << 'EOF' > nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location /evidence {
            proxy_pass http://127.0.0.1:8081/evidence;
            proxy_set_header Host $host;
            proxy_set_header Cookie ""; # AGENT MUST FIX THIS
        }
    }
}
EOF

    # Create firewall.py
    cat << 'EOF' > firewall.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request

class ProxyHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # AGENT MUST FIX THIS
        if self.headers.get('X-Forensics') == 'true':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Blocked by WAF")
            return

        req = urllib.request.Request("http://127.0.0.1:8080" + self.path, method="GET")
        for key, val in self.headers.items():
            req.add_header(key, val)
        try:
            with urllib.request.urlopen(req) as response:
                self.send_response(response.status)
                for k, v in response.headers.items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(response.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()

HTTPServer(('127.0.0.1', 8000), ProxyHTTPRequestHandler).serve_forever()
EOF

    # Create backend.py
    cat << 'EOF' > backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/evidence':
            cookie = self.headers.get('Cookie', '')
            if 'Auth-Token=admin_access' in cookie:
                try:
                    result = subprocess.check_output(['bash', './decrypt.sh'], stderr=subprocess.STDOUT)
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(result)
                except subprocess.CalledProcessError as e:
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b"Decryption failed")
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized: Missing or invalid Cookie")

HTTPServer(('127.0.0.1', 8081), BackendHandler).serve_forever()
EOF

    # Create decrypt.sh
    cat << 'EOF' > decrypt.sh
#!/bin/bash
# TODO: Write openssl command to decrypt evidence.enc to STDOUT
EOF
    chmod +x decrypt.sh

    # Create start script
    cat << 'EOF' > start_services.sh
#!/bin/bash
pkill -f "python3 firewall.py"
pkill -f "python3 backend.py"
nginx -s stop 2>/dev/null
sleep 1

python3 backend.py &
nginx -c /home/user/forensics_lab/nginx.conf &
python3 firewall.py &
echo "Services started."
EOF
    chmod +x start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
