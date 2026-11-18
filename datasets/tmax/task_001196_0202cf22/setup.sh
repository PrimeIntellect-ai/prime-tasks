#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/.ssh/config
Host localhost
    StrictHostKeyChecking no
EOF
    chmod 600 /home/user/.ssh/config

    mkdir -p /home/user/requests
    mkdir -p /home/user/config

    echo "role: editor" > /home/user/requests/alice.txt
    echo "role: viewer" > /home/user/requests/bob.txt
    echo "role: admin" > /home/user/requests/charlie.txt

    cat << 'EOF' > /home/user/mock_idp.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/sync':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            with open('/home/user/idp_received.log', 'a') as f:
                f.write(post_data.decode('utf-8') + '\n')
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 8000), Handler) as httpd:
    httpd.serve_forever()
EOF

    mkdir -p /run/sshd
    chmod -R 777 /home/user
