#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server cron
    pip3 install pytest flask pexpect

    mkdir -p /app

    # Create /app/start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes

cat << 'INNER_EOF' > /tmp/auth_api.py
from flask import Flask
app = Flask(__name__)
@app.route('/health')
def health(): return "OK"
if __name__ == '__main__': app.run(port=8080)
INNER_EOF
python3 /tmp/auth_api.py >/dev/null 2>&1 &

cat << 'INNER_EOF' > /tmp/worker.py
import socket, os, time
sock = "/tmp/worker_health.sock"
if os.path.exists(sock): os.remove(sock)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock)
s.listen(1)
while True:
    conn, addr = s.accept()
    conn.sendall(b"OK")
    conn.close()
INNER_EOF
(sleep 1.5 && python3 /tmp/worker.py >/dev/null 2>&1) &
EOF
    chmod +x /app/start_services.sh

    # Create /app/slow_provision.sh
    cat << 'EOF' > /app/slow_provision.sh
#!/bin/bash
/app/start_services.sh
sleep 15
python3 /app/admin_cli.py init-cluster << 'INNER_EOF' > /home/user/provision.log
admin
supersecret
y
INNER_EOF
echo "*/5 * * * * /app/health_check.py" | crontab -
EOF
    chmod +x /app/slow_provision.sh

    # Create /app/admin_cli.py
    cat << 'EOF' > /app/admin_cli.py
#!/usr/bin/env python3
import sys

if len(sys.argv) > 1 and sys.argv[1] == "init-cluster":
    user = input("Enter admin username: ")
    pwd = input("Enter admin password: ")
    conf = input("Confirm [y/N]: ")
    if user == "admin" and pwd == "supersecret" and conf.lower() == "y":
        print("Cluster initialized successfully.")
        sys.exit(0)
    else:
        print("Failed.")
        sys.exit(1)
EOF
    chmod +x /app/admin_cli.py

    # Create /app/health_check.py
    cat << 'EOF' > /app/health_check.py
#!/usr/bin/env python3
print("Health check OK")
EOF
    chmod +x /app/health_check.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
