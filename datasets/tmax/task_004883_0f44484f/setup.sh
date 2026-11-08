#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis bcrypt

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/auth_config.json
{
  "admin_user": "admin",
  "admin_hash": "5f4dcc3b5aa765d61d8327deb882cf99" 
}
EOF

    cat << 'EOF' > /app/corpus/clean/safe.txt
/dashboard
/users/123/profile
/settings
EOF

    cat << 'EOF' > /app/corpus/evil/payloads.txt
http://malicious.com
//attacker.com/login
javascript:alert(document.cookie)
https://evil.org
EOF

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8000;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request, redirect
app = Flask(__name__)

@app.route('/login')
def login():
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return "Login Page"

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx.conf
nohup python3 /app/app.py &
EOF

    chmod +x /app/start_services.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
