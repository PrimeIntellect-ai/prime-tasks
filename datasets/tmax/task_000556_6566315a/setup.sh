#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssh-server iptables sudo
    pip3 install pytest flask paramiko PyJWT

    # Create users
    useradd -m -s /bin/bash user || true
    useradd -m -s /bin/bash flask_svc || true

    # Create required directories
    mkdir -p /app/flask
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create setup script
    echo '#!/bin/bash\necho "Setup complete."' > /app/setup.sh
    chmod +x /app/setup.sh

    # Ensure Nginx default config exists (empty as requested)
    touch /etc/nginx/sites-available/default

    # Create Flask app stub
    cat << 'EOF' > /app/flask/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    return jsonify({"status": "not implemented"}), 501

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Populate evil corpus
    echo "../../../etc/passwd" > /app/corpora/evil/payload1.txt
    echo "%2e%2e%2f" > /app/corpora/evil/payload2.txt
    echo "..%c0%af" > /app/corpora/evil/payload3.txt
    echo "foo/./bar/../../" > /app/corpora/evil/payload4.txt

    # Populate clean corpus
    echo "report.pdf" > /app/corpora/clean/file1.txt
    echo "image_01.png" > /app/corpora/clean/file2.txt
    echo "archive.tar.gz" > /app/corpora/clean/file3.txt

    # Set permissions
    chmod -R 777 /home/user
