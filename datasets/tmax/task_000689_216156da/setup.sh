#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/corpora
    mkdir -p /app/target_env/nginx
    mkdir -p /app/target_env/flask
    mkdir -p /app/bin

    # Create corpora
    cat << 'EOF' > /app/corpora/clean_urls.txt
https://example.com/login
/dashboard
?next=/profile
/home
https://example.com/settings
EOF

    cat << 'EOF' > /app/corpora/evil_payloads.txt
https:example.com
//evil.com
/\evil.com
http://127.0.0.1%00@evil.com
javascript:alert(1)
data:text/html,<script>alert(1)</script>
EOF

    # Create dummy Flask app
    cat << 'EOF' > /app/target_env/flask/app.py
from flask import Flask, request, redirect
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/login')
def login():
    next_url = request.args.get('next', '/dashboard')
    return redirect(next_url)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create skeleton Nginx config
    cat << 'EOF' > /app/target_env/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name localhost;

        # TODO: Configure reverse proxy to Flask and add CSP header
    }
}
EOF

    # Create mock_iptables
    cat << 'EOF' > /app/bin/mock_iptables
#!/bin/bash
echo "Mock iptables called with args: $@"
EOF
    chmod +x /app/bin/mock_iptables

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
