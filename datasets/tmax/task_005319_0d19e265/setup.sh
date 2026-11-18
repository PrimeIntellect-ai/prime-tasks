#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /home/user/services
    mkdir -p /home/user/data
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/services/tm_api.py
import os
from flask import Flask
import redis

app = Flask(__name__)
r = redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/0'))

@app.route('/health')
def health():
    try:
        r.ping()
        return "OK", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/services/tm_worker.sh
#!/bin/bash
source /home/user/services/worker.conf
while true; do
    sleep 1
done
EOF
    chmod +x /home/user/services/tm_worker.sh

    cat << 'EOF' > /home/user/data/master_keys.txt
welcome_msg
login_btn
logout_btn
EOF

    cat << 'EOF' > /home/user/corpora/clean/clean1.csv
welcome_msg,en-US,Welcome {username}!
login_btn,en-US,Log In
logout_btn,en-US,Log Out
EOF

    cat << 'EOF' > /home/user/corpora/clean/clean2.csv
welcome_msg,es-ES,¡Bienvenido {username}!
login_btn,es-ES,Iniciar sesión
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil1.csv
welcome_msg,en-US,Welcome <script>alert(1)</script>
login_btn,en-US,Log In {
logout_btn,en-US,Log Out }
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil2.csv
welcome_msg,es-ES,javascript:alert(1)
login_btn,es-ES,Iniciar <b>sesión</b>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
