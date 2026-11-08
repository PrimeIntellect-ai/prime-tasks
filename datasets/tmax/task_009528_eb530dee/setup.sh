#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest flask

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/auth.log
Jan 14 10:01:22 server sshd[123]: Accepted publickey for admin
Jan 14 10:05:00 server su: successful for root
Jan 14 10:20:11 server systemd: Started Session 44.
EOF

cat << 'EOF' > /home/user/auth_hashes.txt
2b036c646039eaab95ee367a8ecbd63c051ec7ca3b0fbdfb3b24135ab8f15d91
76de45d1ec5cf0b0dc681bf58414b4de2106a351cf941a8db42c1303254eab8b
01e2c949c2de520dc9970923e200ecf1e58e3eb5183bb90708f325f4a622416b
8dcf1eb596280db514936bb483c65cbe2413eec068f4d9ea5baaa5bfb6c929a7
EOF

cat << 'EOF' > /home/user/backdoor_svc.py
from flask import Flask, request, jsonify
import logging

log = logging.getLogger('werkzeug')
log.disabled = True

app = Flask(__name__)

@app.route('/exfiltrate', methods=['POST'])
def exfiltrate():
    data = request.get_json()
    if data and data.get('auth_token') == '01e2c949c2de520dc9970923e200ecf1e58e3eb5183bb90708f325f4a622416b':
        return "FLAG{h1dd3n_d4t4_r3c0v3r3d_succ3ssfully}", 200
    return "Unauthorized", 401

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=13337)
EOF

cat << 'EOF' > /.singularity.d/env/99-backdoor.sh
if ! pgrep -f backdoor_svc.py > /dev/null; then
    python3 /home/user/backdoor_svc.py > /dev/null 2>&1 &
    sleep 1
fi
EOF

chmod +x /.singularity.d/env/99-backdoor.sh
chmod -R 777 /home/user
