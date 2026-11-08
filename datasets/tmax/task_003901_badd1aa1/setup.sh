#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssh-server curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app/nginx /home/user/app/ssh /run/sshd

    # Flask app
    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, make_response
app = Flask(__name__)

@app.route('/')
def index():
    resp = make_response("Hello World")
    resp.set_cookie('session', '1234567890')
    return resp

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Nginx config
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
worker_processes 1;
pid /home/user/app/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/app/nginx/access.log;
    error_log /home/user/app/nginx/error.log;
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # SSH config
    cat << 'EOF' > /home/user/app/ssh/sshd_config
Port 2222
ListenAddress 127.0.0.1
HostKey /home/user/app/ssh/ssh_host_ed25519_key
PidFile /home/user/app/ssh/sshd.pid
PasswordAuthentication yes
PermitEmptyPasswords yes
StrictModes no
EOF

    # Generate SSH host key
    ssh-keygen -t ed25519 -f /home/user/app/ssh/ssh_host_ed25519_key -N ""
    chmod 777 /home/user/app/ssh/ssh_host_ed25519_key

    # Start script
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
nohup python3 /home/user/app/app.py > /home/user/app/flask.log 2>&1 &
nginx -c /home/user/app/nginx/nginx.conf
# Temporarily fix permissions so sshd can start, then revert to vulnerable state
chmod 600 /home/user/app/ssh/ssh_host_ed25519_key
/usr/sbin/sshd -f /home/user/app/ssh/sshd_config
chmod 777 /home/user/app/ssh/ssh_host_ed25519_key
EOF
    chmod +x /home/user/app/start.sh

    # Restart script
    cat << 'EOF' > /home/user/app/restart.sh
#!/bin/bash
pkill -f "python3 /home/user/app/app.py" || true
nginx -c /home/user/app/nginx/nginx.conf -s stop || true
kill $(cat /home/user/app/ssh/sshd.pid) || true
sleep 1
/home/user/app/start.sh
EOF
    chmod +x /home/user/app/restart.sh

    # Start services for initial state
    /home/user/app/start.sh

    chmod -R 777 /home/user
