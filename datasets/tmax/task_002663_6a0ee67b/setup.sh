#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bastion /home/user/backup /home/user/.ssh /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /home/user/bastion/sshd_config
Port 2222
ListenAddress 127.0.0.1
HostKey /home/user/bastion/ssh_host_ed25519_key
AuthorizedKeysFile /home/user/.ssh/authorized_keys
UsePrivilegeSeparation no
StrictModes no
UsePAM no
PidFile /home/user/bastion/sshd.pid
EOF

    cat << 'EOF' > /app/api.py
from flask import Flask, jsonify
app = Flask(__name__)
@app.route('/status')
def status():
    return jsonify({"status": "ok", "service": "internal_api"})
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Generate Corpora
    ssh-keygen -t rsa -b 1024 -N "" -f /tmp/weak_rsa >/dev/null 2>&1
    cp /tmp/weak_rsa.pub /app/corpus/evil/weak_rsa.pub
    ssh-keygen -t ed25519 -N "" -f /tmp/evil_cmd >/dev/null 2>&1
    echo 'command="/bin/sh" '"$(cat /tmp/evil_cmd.pub)" > /app/corpus/evil/cmd_key.pub
    ssh-keygen -t ed25519 -N "" -C "sysadmin_user" -f /tmp/evil_comment >/dev/null 2>&1
    cp /tmp/evil_comment.pub /app/corpus/evil/comment_key.pub

    ssh-keygen -t rsa -b 2048 -N "" -C "user1" -f /tmp/clean_rsa >/dev/null 2>&1
    cp /tmp/clean_rsa.pub /app/corpus/clean/clean_rsa.pub
    ssh-keygen -t ed25519 -N "" -C "user2" -f /tmp/clean_ed >/dev/null 2>&1
    cp /tmp/clean_ed.pub /app/corpus/clean/clean_ed.pub

    chown -R user:user /home/user /app
    chmod 700 /home/user/.ssh
    chmod -R 777 /home/user
