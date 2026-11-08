#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_service.py
#!/usr/bin/env python3
import http.server
import socketserver
import urllib.parse

class VulnerableHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        if parsed_path.path == "/login":
            query = urllib.parse.parse_qs(parsed_path.query)
            if "next" in query:
                redirect_url = query["next"][0]
                self.send_response(302)
                self.send_header("Location", redirect_url)
                self.send_header("Set-Cookie", "session=deleted; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT")
                self.end_headers()
                return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", 8000), VulnerableHandler) as httpd:
        httpd.serve_forever()
EOF
    chmod +x /home/user/auth_service.py

    chmod -R 777 /home/user
