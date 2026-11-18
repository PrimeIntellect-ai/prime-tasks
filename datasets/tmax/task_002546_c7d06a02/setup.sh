#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server zip unzip
    pip3 install pytest flask redis gunicorn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location /upload {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/receiver.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if not file:
        return 'No file', 400
    filepath = '/tmp/' + file.filename
    file.save(filepath)
    # Missing redis logic here
    return 'OK', 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create corpora
    cd /tmp

    # Clean 1
    mkdir -p clean1/nested
    echo "Documentation content" > clean1/docs.md
    echo "Fake image" > clean1/nested/image.png
    cd clean1/nested && zip ../images.zip image.png && cd ../..
    cd clean1 && zip ../clean1.zip docs.md images.zip && cd ..
    mv clean1.zip /home/user/corpora/clean/

    # Clean 2
    mkdir -p clean2
    echo "Some notes" > clean2/notes.txt
    cd clean2 && zip ../clean2.zip notes.txt && cd ..
    mv clean2.zip /home/user/corpora/clean/

    # Evil corrupt
    echo "This is definitely not a valid zip file, it is corrupted." > /home/user/corpora/evil/corrupt.zip

    # Evil bomb
    dd if=/dev/zero of=huge_file.txt bs=1M count=2
    zip bomb.zip huge_file.txt
    mv bomb.zip /home/user/corpora/evil/

    chmod -R 777 /home/user
