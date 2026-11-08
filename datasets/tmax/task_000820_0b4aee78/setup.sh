#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/vuln_app/uploads
    mkdir -p /home/user/audit_configs/sudoers.d/

    echo "Flask==2.3.3" > /home/user/vuln_app/requirements.txt
    echo "Werkzeug==2.3.7" >> /home/user/vuln_app/requirements.txt

    cat << 'EOF' > /home/user/vuln_app/app.py
import os
import datetime
from flask import Flask, request

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    filename = file.filename

    # Vulnerable path traversal logic
    upload_dir = '/home/user/vuln_app/uploads'
    target_path = os.path.abspath(os.path.join(upload_dir, filename))

    file.save(target_path)

    # Logging
    timestamp = datetime.datetime.now().strftime("%d/%b/%Y:%H:%M:%S")
    with open('/home/user/vuln_app/access.log', 'a') as f:
        f.write(f"[{timestamp}] UPLOAD {filename} SUCCESS\n")

    return "Success", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443, ssl_context=('/home/user/vuln_app/certs/server.crt', '/home/user/vuln_app/certs/server.key'))
EOF

    echo "\%sysadmin ALL=(ALL:ALL) ALL" | sed 's/\\//' > /home/user/audit_configs/sudoers.d/10-sysadmins

    cat << 'EOF' > /home/user/audit_configs/sudoers.d/20-devops
backup_svc ALL=(root) NOPASSWD: /usr/bin/rsync
cicd_runner ALL=(ALL) NOPASSWD: /usr/bin/find
EOF

    cat << 'EOF' > /home/user/audit_configs/sudoers.d/30-monitoring
nagios ALL=(root) NOPASSWD: /usr/sbin/service
EOF

    chown -R user:user /home/user/vuln_app
    chown -R user:user /home/user/audit_configs
    chmod -R 777 /home/user
