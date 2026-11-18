#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        openssh-server \
        curl \
        jq \
        logrotate

    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /app/ssh /app/nginx /app/logs /app/scripts

    # Generate SSH keys
    ssh-keygen -t rsa -b 2048 -f /app/ssh/deploy_key -N ""
    cp /app/ssh/deploy_key.pub /app/ssh/authorized_keys
    ssh-keygen -t rsa -b 2048 -f /app/ssh/ssh_host_rsa_key -N ""

    # Create sshd_config
    cat << 'EOF' > /app/ssh/sshd_config
Port 2222
HostKey /app/ssh/ssh_host_rsa_key
PidFile /app/ssh/sshd.pid
StrictModes no
AuthorizedKeysFile /dev/null
PasswordAuthentication no
PubkeyAuthentication yes
EOF

    # Create backend.py
    cat << 'EOF' > /app/scripts/backend.py
import logging
from flask import Flask, jsonify

app = Flask(__name__)

# Configure logging
logging.basicConfig(filename='/app/logs/backend.log', level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')

@app.route('/')
def index():
    app.logger.info("Request received")
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

    # Create nginx.conf
    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
pid /app/nginx/nginx.pid;
error_log /app/logs/nginx_error.log;

events {
    worker_connections 1024;
}

http {
    access_log /app/logs/nginx_access.log;
    client_body_temp_path /app/nginx/client_body;
    fastcgi_temp_path /app/nginx/fastcgi_temp;
    proxy_temp_path /app/nginx/proxy_temp;
    scgi_temp_path /app/nginx/scgi_temp;
    uwsgi_temp_path /app/nginx/uwsgi_temp;

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            # proxy_pass directive missing
        }
    }
}
EOF
    mkdir -p /app/nginx/client_body /app/nginx/fastcgi_temp /app/nginx/proxy_temp /app/nginx/scgi_temp /app/nginx/uwsgi_temp

    # Create benchmark.sh
    cat << 'EOF' > /app/scripts/benchmark.sh
#!/bin/bash

TOTAL=500
SUCCESS=0

for i in $(seq 1 $TOTAL); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/)
    if [ "$STATUS" == "200" ]; then
        SUCCESS=$((SUCCESS+1))
    fi
done

RATE=$(echo "scale=2; $SUCCESS / $TOTAL" | bc -l)
echo "{\"success_rate\": $RATE}"
EOF
    chmod +x /app/scripts/benchmark.sh

    # Create manage_services.sh
    cat << 'EOF' > /app/scripts/manage_services.sh
#!/bin/bash

ACTION=$1
SERVICE=$2

if [ "$ACTION" == "start" ]; then
    if [ "$SERVICE" == "sshd" ]; then
        /usr/sbin/sshd -f /app/ssh/sshd_config
    elif [ "$SERVICE" == "nginx" ]; then
        /usr/sbin/nginx -c /app/nginx/nginx.conf
    elif [ "$SERVICE" == "backend" ]; then
        nohup python3 /app/scripts/backend.py > /dev/null 2>&1 &
        echo $! > /app/scripts/backend.pid
    fi
elif [ "$ACTION" == "stop" ]; then
    if [ "$SERVICE" == "sshd" ]; then
        kill $(cat /app/ssh/sshd.pid) 2>/dev/null || true
    elif [ "$SERVICE" == "nginx" ]; then
        /usr/sbin/nginx -c /app/nginx/nginx.conf -s stop 2>/dev/null || true
    elif [ "$SERVICE" == "backend" ]; then
        kill $(cat /app/scripts/backend.pid) 2>/dev/null || true
    fi
elif [ "$ACTION" == "restart" ]; then
    $0 stop $SERVICE
    sleep 1
    $0 start $SERVICE
fi
EOF
    chmod +x /app/scripts/manage_services.sh

    # Set permissions
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user

    # Start backend
    su - user -c "/app/scripts/manage_services.sh start backend"
