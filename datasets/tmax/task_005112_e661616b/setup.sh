#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx sudo curl
    pip3 install pytest flask gunicorn requests

    # Create app directory
    mkdir -p /app/capacity-planner-1.0.0
    mkdir -p /app/nginx

    # Create Flask app
    cat << 'EOF' > /app/capacity-planner-1.0.0/app.py
from flask import Flask
import time

app = Flask(__name__)

@app.route('/analyze')
def analyze():
    time.sleep(0.2)
    return "Analysis complete\n"

if __name__ == '__main__':
    app.run()
EOF

    # Create startup script
    cat << 'EOF' > /app/capacity-planner-1.0.0/start.sh
#!/bin/bash
gunicorn --bind unix:/var/run/capacity.sock app:app --daemon
EOF
    chmod +x /app/capacity-planner-1.0.0/start.sh

    # Create Nginx config
    cat << 'EOF' > /app/nginx/capacity.conf
server {
    listen 8080;
    server_name localhost;

    location /analyze {
        proxy_pass http://unix:/tmp/backend.sock;
    }
}
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Set permissions
    chown -R user:user /app
    chmod -R 777 /home/user
