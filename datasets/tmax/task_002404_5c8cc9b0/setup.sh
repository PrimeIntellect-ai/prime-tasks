#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssh-server curl gunicorn
    pip3 install pytest flask paramiko

    # Create directories
    mkdir -p /app/backend
    mkdir -p /app/sshd
    mkdir -p /app/nginx
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/test_set

    # Create /app/backend/flask_app.py
    cat << 'EOF' > /app/backend/flask_app.py
import subprocess
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/trigger', methods=['GET'])
def trigger():
    try:
        proc = subprocess.Popen(['python3', '/app/backend/helper.py', '--user', 'target', '--password', 'supersecret123'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = proc.communicate()
        if proc.returncode == 0:
            return jsonify({"status": "success"})
        else:
            return jsonify({"status": "error", "message": err.decode()})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create /app/backend/helper.py
    cat << 'EOF' > /app/backend/helper.py
import argparse
import paramiko
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--user', required=True)
    parser.add_argument('--password', required=True)
    args = parser.parse_args()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect('127.0.0.1', port=2222, username=args.user, password=args.password)
        stdin, stdout, stderr = client.exec_command('echo success')
        print(stdout.read().decode())
        client.close()
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

    # Create /app/sshd/sshd_config
    cat << 'EOF' > /app/sshd/sshd_config
Port 2222
PasswordAuthentication yes
PubkeyAuthentication yes
HostKey /app/sshd/ssh_host_rsa_key
PidFile /app/sshd/sshd.pid
AuthorizedKeysFile /app/sshd/authorized_keys
StrictModes no
UsePAM no
EOF

    ssh-keygen -t rsa -f /app/sshd/ssh_host_rsa_key -N ''

    # Create /app/start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
pkill -f gunicorn || true
pkill -f sshd || true
pkill -f nginx || true

/usr/sbin/sshd -f /app/sshd/sshd_config

cd /app/backend
gunicorn -w 1 -b 127.0.0.1:5000 flask_app:app --daemon

cat << 'NGINX' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
NGINX
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start_services.sh

    # Populate corpora
    echo "eyJ1c2VybmFtZSI6ICJhZG1pbiIsICJjb21tYW5kIjogImxzIn0=" > /home/user/corpora/clean/clean1.txt
    echo "eyJ1c2VybmFtZSI6ICJhZG1pbiIsICJjb21tYW5kIjogImxzIn0=" > /home/user/corpora/test_set/clean1.txt

    echo "eyJ1c2VybmFtZSI6ICJhZG1pbiIsICJjb21tYW5kIjogImxzIDsgcm0gLXJmIC8ifQ==" > /home/user/corpora/evil/evil1.txt
    echo "eyJ1c2VybmFtZSI6ICJhZG1pbiIsICJjb21tYW5kIjogImxzIDsgcm0gLXJmIC8ifQ==" > /home/user/corpora/test_set/evil1.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
