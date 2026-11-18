#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make tar curl
    pip3 install pytest

    mkdir -p /app/archive-service-1.2.0
    cd /app/archive-service-1.2.0

    cat << 'EOF' > Makefile
DESTDIR=/usr/local/bin

install:
	mkdir -p $(DESTDIR)
	cp run.sh server.py config.ini $(DESTDIR)/
	chmod +x $(DESTDIR)/run.sh
EOF

    cat << 'EOF' > config.ini
PORT=8080
UPLOAD_DIR=/tmp/uploads
EOF

    cat << 'EOF' > run.sh
#!/bin/bash
# Read config
PORT=$(grep '^PORT=' config.ini | cut -d= -f2)
UPLOAD_DIR=$(grep '^UPLOAD_DOR=' config.ini | cut -d= -f2)

python3 server.py --port $PORT --upload-dir $UPLOAD_DIR
EOF
    chmod +x run.sh

    cat << 'EOF' > server.py
import sys
import os
import tarfile
from http.server import HTTPServer, BaseHTTPRequestHandler
import argparse

class ArchiveHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/upload':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            tmp_tar = "temp.tar"
            with open(tmp_tar, "wb") as f:
                f.write(body)

            # Vulnerable extraction
            os.system(f"tar -xf {tmp_tar} -C {self.server.upload_dir}")
            os.remove(tmp_tar)

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Uploaded")

    def do_GET(self):
        if self.path.startswith('/files/'):
            filename = self.path[len('/files/'):]
            filepath = os.path.join(self.server.upload_dir, filename)
            if os.path.exists(filepath):
                with open(filepath, 'rb') as f:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--upload-dir', type=str, default='/tmp/uploads')
    args = parser.parse_args()

    os.makedirs(args.upload_dir, exist_ok=True)

    server = HTTPServer(('0.0.0.0', args.port), ArchiveHandler)
    server.upload_dir = args.upload_dir
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
