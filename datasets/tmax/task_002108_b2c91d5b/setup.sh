#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl logrotate
pip3 install pytest

useradd -m -s /bin/bash user || true

# Create directories
mkdir -p /home/user/nginx/logs
mkdir -p /home/user/nginx/client_body
mkdir -p /home/user/nginx/fastcgi_temp
mkdir -p /home/user/nginx/proxy_temp
mkdir -p /home/user/nginx/scgi_temp
mkdir -p /home/user/nginx/uwsgi_temp
mkdir -p /home/user/backend
mkdir -p /home/user/corpora

# Create Nginx config
cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

# Create corpora
cat << 'EOF' > /home/user/corpora/evil.txt
GET /?q=<script>alert(1)</script> HTTP/1.1
POST /api/login HTTP/1.1\nBody: user=admin' UNION SELECT * FROM users--
GET /../../../../etc/passwd HTTP/1.1
EOF

cat << 'EOF' > /home/user/corpora/clean.txt
GET /index.html HTTP/1.1
POST /api/data HTTP/1.1
GET /images/logo.png HTTP/1.1
EOF

# Create backend response
echo "OK" > /home/user/backend/index.html

# Create startup script
cat << 'EOF' > /home/user/nginx/start.sh
#!/bin/bash
cd /home/user/backend
nohup python3 -m http.server 8081 --bind 127.0.0.1 > /dev/null 2>&1 &
nginx -c /home/user/nginx/nginx.conf
EOF
chmod +x /home/user/nginx/start.sh

# Touch initial log files
touch /home/user/nginx/logs/access.log
touch /home/user/nginx/logs/error.log

chmod -R 777 /home/user
