#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app
cd /home/user/app

# 1. Create the secret flag
echo -n "CTF{py7h0n_byt3c0d3_s3cr3t5_19283}" > /home/user/flag.txt

# 2. Create the auth module
cat << 'EOF' > auth.py
def verify_session(cookie_val):
    secret = "Adm1n_T0k3n_X99"
    return cookie_val == secret
EOF

# 3. Compile the auth module and remove source
python3 -c "import py_compile; py_compile.compile('auth.py', cfile='auth.pyc')"
rm auth.py

# 4. Create the vulnerable web server
cat << 'EOF' > app.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import os
import auth

class VulnerableHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)

        if parsed_path.path == '/api/system':
            # Check cookie
            headers = self.headers.get('Cookie', '')
            session_cookie = ''
            for cookie in headers.split(';'):
                if 'session=' in cookie:
                    session_cookie = cookie.split('session=')[1].strip()

            if not auth.verify_session(session_cookie):
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden: Invalid or missing session cookie.")
                return

            # Vulnerable logic: command injection
            query = urllib.parse.parse_qs(parsed_path.query)
            cmd = query.get('cmd', [''])[0]

            if cmd:
                # Intentionally vulnerable to command injection
                output = os.popen(cmd).read()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(output.encode())
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad Request: Missing cmd parameter.")
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8000)
    httpd = HTTPServer(server_address, VulnerableHandler)
    httpd.serve_forever()
EOF

chmod -R 777 /home/user
