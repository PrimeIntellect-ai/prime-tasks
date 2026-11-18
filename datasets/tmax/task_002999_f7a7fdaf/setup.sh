#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx git curl procps
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/nginx/client_temp
mkdir -p /home/user/nginx/proxy_temp
mkdir -p /home/user/nginx/fastcgi_temp
mkdir -p /home/user/nginx/uwsgi_temp
mkdir -p /home/user/nginx/scgi_temp
mkdir -p /home/user/backend.git
mkdir -p /home/user/workspace
mkdir -p /home/user/deployed_app

cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /home/user/nginx/client_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    access_log /home/user/nginx/access.log;
    error_log /home/user/nginx/error.log;

    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

cd /home/user/backend.git
git init --bare

cd /home/user/workspace
git init

cat << 'EOF' > app.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Hello from Backend!")

if __name__ == '__main__':
    PORT = 9001
    server = HTTPServer(('127.0.0.1', PORT), SimpleHandler)
    server.serve_forever()
EOF

git config --global user.email "user@example.com"
git config --global user.name "User"
git add app.py
git commit -m "Initial commit"
git remote add origin /home/user/backend.git
git push origin master

# Create a startup script to ensure Nginx is running when the container is executed
mkdir -p /.singularity.d/env
cat << 'EOF' > /.singularity.d/env/99-start-nginx.sh
#!/bin/bash
if ! pgrep -x "nginx" > /dev/null; then
    nginx -c /home/user/nginx/nginx.conf || true
fi
EOF
chmod +x /.singularity.d/env/99-start-nginx.sh

chown -R user:user /home/user
chmod -R 777 /home/user
