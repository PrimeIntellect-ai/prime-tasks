#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip supervisor curl tar
    pip3 install pytest flask requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archive /home/user/deploy /home/user/certs
    cd /home/user/archive

    # Create v1 app
    cat << 'EOF' > app.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "APP_VERSION_1_RESTORED"
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF
    tar -czvf v1.tar.gz app.py
    rm app.py

    # Create v2 app
    cat << 'EOF' > app.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "APP_VERSION_2_RESTORED"
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF
    tar -czvf v2.tar.gz app.py
    rm app.py

    chmod -R 777 /home/user
