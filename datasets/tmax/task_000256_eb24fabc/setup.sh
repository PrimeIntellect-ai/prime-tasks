#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server socat curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app/ssh
    mkdir -p /home/user/app/router
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/.ssh
    mkdir -p /run/sshd

    # Generate SSH key
    ssh-keygen -t ed25519 -f /home/user/test_key -N ""
    cp /home/user/test_key.pub /home/user/.ssh/authorized_keys
    chmod 777 /home/user/.ssh/authorized_keys

    # SSH config
    cat << 'EOF' > /home/user/app/ssh/sshd_config
Port 2222
ListenAddress 127.0.0.1
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
AuthorizedKeysFile /home/user/.ssh/authorized_keys
StrictModes yes
PasswordAuthentication no
PubkeyAuthentication yes
PidFile /home/user/app/ssh/sshd.pid
EOF

    # Router config
    cat << 'EOF' > /home/user/app/router/routes.conf
backend=127.0.0.1:9999
EOF

    # Router script
    cat << 'EOF' > /home/user/app/router/router.sh
#!/bin/bash
while true; do
    DEST=$(grep '^backend=' /home/user/app/router/routes.conf | cut -d= -f2)
    if [ -z "$DEST" ]; then DEST="127.0.0.1:9999"; fi
    socat TCP-LISTEN:8080,fork,reuseaddr TCP:$DEST
    sleep 1
done
EOF

    # Backend script
    cat << 'EOF' > /home/user/app/backend/server.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/api/status')
def status():
    return jsonify({"status": "ok", "service": "backend"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
