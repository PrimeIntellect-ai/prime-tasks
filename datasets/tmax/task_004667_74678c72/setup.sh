#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx binutils build-essential procps
    pip3 install pytest flask redis

    mkdir -p /home/user/services/api /home/user/staging /home/user/sanitizer /home/user/corpora/clean /home/user/corpora/evil

    # Create dummy ELF files
    cat << 'EOF' > /tmp/dummy.c
int main() { return 0; }
EOF
    gcc /tmp/dummy.c -o /tmp/clean_base.elf

    for i in $(seq 1 50); do
        cp /tmp/clean_base.elf /home/user/corpora/clean/clean_${i}.elf

        echo "G1 X10 Y20 Z-5.0" > /tmp/evil_payload.txt
        objcopy --add-section .cnc_gcode=/tmp/evil_payload.txt /tmp/clean_base.elf /home/user/corpora/evil/evil_${i}.elf
    done

    # Create app.py
    cat << 'EOF' > /home/user/services/api/app.py
from flask import Flask, request
import redis
import os

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file", 400
    file = request.files['file']
    filepath = os.path.join('/home/user/staging', file.filename)
    file.save(filepath)
    # Missing sanitizer invocation
    r.set(file.filename, 'uploaded')
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Configure nginx
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    location /upload {
        proxy_pass http://127.0.0.1:5000/upload;
    }
}
EOF

    # Start services on exec
    cat << 'EOF' > /.singularity.d/env/99-services.sh
if ! pgrep -x redis-server > /dev/null; then
    redis-server --daemonize yes
fi
if ! pgrep -x nginx > /dev/null; then
    nginx
fi
if ! pgrep -f "python3 /home/user/services/api/app.py" > /dev/null; then
    nohup python3 /home/user/services/api/app.py > /dev/null 2>&1 &
    sleep 1
fi
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
