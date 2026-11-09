#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo curl wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo -n "01e9d1bfb9b0091bf2e4bb2e604ec282" > /home/user/hash.txt

    cat << 'EOF' > /home/user/server.py
import http.server
import socketserver
import urllib.parse

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/login':
            length = int(self.headers['Content-Length'])
            post_data = urllib.parse.parse_qs(self.rfile.read(length).decode('utf-8'))
            if post_data.get('pin', [''])[0] == '4729':
                self.send_response(200)
                self.send_header('Set-Cookie', 'session=valid_user_session')
                self.end_headers()
                self.wfile.write(b'Logged in')
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'Fail')

    def do_GET(self):
        if self.path.startswith('/redirect'):
            cookie = self.headers.get('Cookie', '')
            if 'session=valid_user_session' in cookie:
                qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                target = qs.get('target', ['/'])[0]
                self.send_response(302)
                self.send_header('Location', target)
                self.end_headers()
            else:
                self.send_response(403)
                self.end_headers()
        elif self.path == '/dashboard':
            cookie = self.headers.get('Cookie', '')
            if 'session=valid_user_session' in cookie:
                self.send_response(200)
                self.send_header('X-Secret-Token', 'Tok_99182')
                self.end_headers()
                self.wfile.write(b'Welcome to dashboard')
            else:
                self.send_response(403)
                self.end_headers()

httpd = socketserver.TCPServer(("127.0.0.1", 5000), Handler)
httpd.serve_forever()
EOF

    echo -n "FLAG{privesc_base64_succ3ss}" > /var/root_secret.txt
    chown root:root /var/root_secret.txt
    chmod 600 /var/root_secret.txt

    echo "user ALL=(ALL) NOPASSWD: /usr/bin/base64" > /etc/sudoers.d/user_base64
    echo "root ALL=(ALL) NOPASSWD: /usr/bin/base64" >> /etc/sudoers.d/user_base64
    chmod 440 /etc/sudoers.d/user_base64

    chmod -R 777 /home/user
