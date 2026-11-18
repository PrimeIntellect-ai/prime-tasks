#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-flask curl openssl sudo iputils-ping
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    cd /home/user/certs

    # Generate CA
    openssl req -x509 -newkey rsa:4096 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=Internal_CA"

    # Generate Server Cert
    openssl req -newkey rsa:4096 -keyout server.key -out server.csr -nodes -subj "/CN=127.0.0.1"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

    # Generate Client Cert
    openssl req -newkey rsa:4096 -keyout client.key -out client.csr -nodes -subj "/CN=PenTester"
    openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 365

    # Mess up client key permissions
    chmod 777 client.key

    # Create the vulnerable service
    cat << 'EOF' > /home/user/server.py
import os
import subprocess
from flask import Flask, request
import ssl

app = Flask(__name__)

@app.route('/network_test', methods=['GET'])
def network_test():
    host = request.args.get('host', '')

    # Input validation bypass required
    if any(char in host for char in [' ', ';', '&', '|']):
        return "Security Policy Violation: Invalid characters detected.", 403

    try:
        # Vulnerable command execution
        cmd = f"ping -c 1 {host}"
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, text=True)
        return f"Ping Results:\n{output}"
    except subprocess.CalledProcessError as e:
        return f"Error executing ping:\n{e.output}", 500

if __name__ == '__main__':
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(certfile='/home/user/certs/server.crt', keyfile='/home/user/certs/server.key')
    context.load_verify_locations(cafile='/home/user/certs/ca.crt')

    # Set the flag in the environment
    os.environ['FLAG'] = "SECURE_FLAG_{mTLS_and_c0mmand_inj3ction_m4ster}"

    app.run(host='127.0.0.1', port=8443, ssl_context=context)
EOF

    chmod +x /home/user/server.py
    chown -R user:user /home/user/certs /home/user/server.py

    # Create a startup script to run the server in the background
    cat << 'EOF' > /home/user/start_server.sh
#!/bin/bash
sudo -u user nohup python3 /home/user/server.py > /dev/null 2>&1 &
sleep 2
EOF
    chmod +x /home/user/start_server.sh

    # Add to bashrc so it starts when user logs in/runs bash
    echo "/home/user/start_server.sh" >> /home/user/.bashrc
    echo "/home/user/start_server.sh" >> /root/.bashrc

    chmod -R 777 /home/user
