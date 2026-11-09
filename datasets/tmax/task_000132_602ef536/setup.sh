#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl libcurl4-openssl-dev build-essential cron
    pip3 install pytest flask

    mkdir -p /app
    cat << 'EOF' > /app/git_server.py
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

class GitHandler(BaseHTTPRequestHandler):
    def do_GET(self): self.handle_req()
    def do_POST(self): self.handle_req()
    def handle_req(self):
        env = os.environ.copy()
        env['GIT_PROJECT_ROOT'] = '/home/user/gitserver'
        env['GIT_HTTP_EXPORT_ALL'] = '1'
        env['REQUEST_METHOD'] = self.command
        env['PATH_INFO'] = self.path
        env['QUERY_STRING'] = self.path.split('?')[1] if '?' in self.path else ''
        env['CONTENT_TYPE'] = self.headers.get('Content-Type', '')
        env['CONTENT_LENGTH'] = self.headers.get('Content-Length', '')

        proc = subprocess.Popen(['/usr/lib/git-core/git-http-backend'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        body = self.rfile.read(int(env['CONTENT_LENGTH'])) if env['CONTENT_LENGTH'] else b''
        out, _ = proc.communicate(body)

        headers, _, res_body = out.partition(b'\r\n\r\n')
        self.send_response(200)
        for header in headers.split(b'\r\n'):
            if header:
                k, v = header.split(b': ', 1)
                self.send_header(k.decode(), v.decode())
        self.end_headers()
        self.wfile.write(res_body)

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8000), GitHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/k8s_mock.py
from flask import Flask, request, jsonify

app = Flask(__name__)
count = 0

@app.route('/apply', methods=['POST'])
def apply():
    global count
    count += 1
    return jsonify({"status": "ok", "count": count})

@app.route('/sync', methods=['GET'])
def sync():
    return jsonify({"status": "synced"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nohup python3 /app/git_server.py > /app/git.log 2>&1 &
nohup python3 /app/k8s_mock.py > /app/k8s.log 2>&1 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/gitserver/manifests.git
    cd /home/user/gitserver/manifests.git && git init --bare
    git config --file config http.receivepack true

    /app/start_services.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
