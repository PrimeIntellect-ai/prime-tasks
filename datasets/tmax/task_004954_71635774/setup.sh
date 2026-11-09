#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /app/start.sh
#!/bin/bash
cd /app
python3 app.py &
sleep 2
nginx -c /app/nginx.conf
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/app.py
from flask import Flask

app = Flask(__name__)

@app.route('/login')
def login():
    return "Login", 200

@app.route('/admin')
def admin():
    return "Admin", 200

@app.route('/')
def index():
    return "Index", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 80;
        location / {
            # proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/corpus/evil/1.txt
http://evil.com/login
https://myapp.local.evil.com/
//malicious.site/
javascript:alert(1)
data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
EOF

    cat << 'EOF' > /app/corpus/clean/1.txt
/dashboard
/profile?user=1
https://myapp.local/settings
https://myapp.local/
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
