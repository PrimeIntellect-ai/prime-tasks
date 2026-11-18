#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app
    mkdir -p /home/user/cicd

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/logs/access.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/server.py
import http.server
import socketserver

PORT = 9000

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend Service Operational")

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/cicd/deploy.sh
#!/bin/bash
echo "Deploying application..."
# Kill existing instances
pkill -f "python3 /home/user/app/server.py" || true
# Start backend
python3 /home/user/app/server.py &
echo "Deployment finished."
EOF

    chmod +x /home/user/cicd/deploy.sh

    chmod -R 777 /home/user
