#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl jq procps
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_data.csv
id,full_name,role
1,Alice Smith,admin
2,Bob Jones,user
3,Charlie Brown,editor
4,Diana Prince,admin
EOF

    cat << 'EOF' > /home/user/mock_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class MockAPI(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/import':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                # Basic validation
                if 'identifier' in data and 'display_name' in data and 'is_admin' in data:
                    self.send_response(201)
                    self.end_headers()
                    self.wfile.write(b"Created")
                else:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b"Bad Schema")
            except:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Invalid JSON")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 9000)
    httpd = HTTPServer(server_address, MockAPI)
    httpd.serve_forever()
EOF

    # Ensure the mock server starts when a shell is opened
    cat << 'EOF' >> /etc/bash.bashrc
if ! pgrep -f mock_server.py > /dev/null; then
    python3 /home/user/mock_server.py &
    sleep 1
fi
EOF

    cat << 'EOF' >> /etc/profile
if ! pgrep -f mock_server.py > /dev/null; then
    python3 /home/user/mock_server.py &
    sleep 1
fi
EOF

    # Also wrap pytest to ensure it runs during testing if not invoked via bash
    mv /usr/local/bin/pytest /usr/local/bin/pytest_orig
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
if ! pgrep -f mock_server.py > /dev/null; then
    python3 /home/user/mock_server.py &
    sleep 1
fi
exec /usr/local/bin/pytest_orig "$@"
EOF
    chmod +x /usr/local/bin/pytest

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
