#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_project/logs

    cat << 'EOF' > /home/user/api_project/server.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/merge_sort':
            length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(length)
            data = json.loads(post_data)

            combined = data.get('list1', []) + data.get('list2', [])

            # Legacy Python 2 sort
            def compare(x, y):
                return (x['id'] > y['id']) - (x['id'] < y['id'])

            # This will fail in Py3
            combined.sort(cmp=compare)

            # This will also fail in Py3
            for k, v in data.iteritems():
                pass

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(combined).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/api_project/nginx.conf
events {
    worker_connections 1024;
}

http {
    access_log /home/user/api_project/logs/access.log;
    error_log /home/user/api_project/logs/error.log;

    server {
        listen 8000;
        server_name localhost;

        location /api/ {
            # BUG: Wrong port, should be 8080
            proxy_pass http://127.0.0.1:8081;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    chown -R user:user /home/user/api_project
    chmod -R 777 /home/user
