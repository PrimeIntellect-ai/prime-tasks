#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /app/vendored_sso_v1.2

    cat << 'EOF' > /app/vendored_sso_v1.2/app.py
from flask import Flask, request, redirect

app = Flask(__name__)

@app.route('/login')
def login():
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('/dashboard')

if __name__ == '__main__':
    import sys
    port = 5000
    if len(sys.argv) > 2 and sys.argv[1] == '--port':
        try:
            port = int(sys.argv[2])
        except ValueError:
            pass
    app.run(host='127.0.0.1', port=port)
EOF

    cat << 'EOF' > /app/vendored_sso_v1.2/run.sh
#!/bin/bash
python3 /app/vendored_sso_v1.2/app.py --port $APP_PORT
EOF
    chmod +x /app/vendored_sso_v1.2/run.sh

    cat << 'EOF' > /home/user/historical_access.log
10.0.0.5 - - [12/Nov/2023:08:12:31 +0000] "GET /login?next=http://evil.com HTTP/1.1" 302 123 "-" "Mozilla/5.0"
192.168.1.50 - - [12/Nov/2023:08:15:00 +0000] "GET /login?next=/settings HTTP/1.1" 200 456 "-" "Mozilla/5.0"
10.0.0.8 - - [12/Nov/2023:08:20:11 +0000] "GET /login?next=https://attacker.net/auth HTTP/1.1" 302 123 "-" "Mozilla/5.0"
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
