#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server build-essential
pip3 install pytest flask waitress

# Configure Nginx to listen on 8080 and proxy to Flask on 5000
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    location / {
        proxy_pass http://127.0.0.1:5000;
    }
}
EOF

# Create Flask app directory
mkdir -p /app/flask_app

# Create Flask app script
cat << 'EOF' > /app/flask_app/app.py
from flask import Flask, request
import configparser
import subprocess
import os
import tempfile

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    config = configparser.ConfigParser()
    config.read('/app/flask_app/config.ini')
    filter_cmd = config.get('Upload', 'FILTER_CMD', fallback="")

    if not filter_cmd:
        return "No filter configured", 500

    data = request.get_data()
    fd, path = tempfile.mkstemp()
    with os.fdopen(fd, 'wb') as f:
        f.write(data)

    try:
        ret = subprocess.call([filter_cmd, path])
        if ret == 0:
            return "OK", 200
        else:
            return "Bad Request", 400
    except Exception as e:
        return str(e), 500
    finally:
        os.remove(path)

if __name__ == '__main__':
    from waitress import serve
    serve(app, host='127.0.0.1', port=5000)
EOF

# Create config.ini
cat << 'EOF' > /app/flask_app/config.ini
[Upload]
FILTER_CMD=
EOF

# Create user and corpus directories
useradd -m -s /bin/bash user || true
mkdir -p /home/user/corpus/clean
mkdir -p /home/user/corpus/evil

# Generate sample binary files
python3 -c "
import struct
with open('/home/user/corpus/clean/1.chnk', 'wb') as f:
    f.write(b'CHNK' + struct.pack('<I', 2) + struct.pack('<I', 10) + b'A'*10 + struct.pack('<I', 5) + b'B'*5)
with open('/home/user/corpus/evil/1.chnk', 'wb') as f:
    f.write(b'BADD' + struct.pack('<I', 0))
with open('/home/user/corpus/evil/2.chnk', 'wb') as f:
    f.write(b'CHNK' + struct.pack('<I', 1) + struct.pack('<I', 1048577) + b'A'*1048577)
with open('/home/user/corpus/evil/3.chnk', 'wb') as f:
    f.write(b'CHNK' + struct.pack('<I', 1) + struct.pack('<I', 100) + b'A'*50)
with open('/home/user/corpus/evil/4.chnk', 'wb') as f:
    f.write(b'CHNK' + struct.pack('<I', 0) + b'X')
"

# Set permissions
chmod -R 777 /app/flask_app
chmod -R 777 /home/user
