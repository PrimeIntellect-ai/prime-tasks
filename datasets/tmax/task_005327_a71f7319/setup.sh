#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask requests redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/staging
    mkdir -p /home/user/app/storage
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /home/user/app/storage && python3 -m http.server 8000 &
export FLASK_APP=/home/user/app/gateway.py
flask run --host=127.0.0.1 --port=5000 &
wait
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/gateway.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400

    # Original vulnerable implementation
    save_path = os.path.join('/home/user/app/storage', file.filename)
    file.save(save_path)
    return "Uploaded", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /tmp/generate_corpora.py
import struct
import zlib
import os

def create_czip(path, magic, size, filename, payload_data):
    filename_bytes = filename.encode('ascii')
    payload = zlib.compress(payload_data)

    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', size))
        f.write(struct.pack('<H', len(filename_bytes)))
        f.write(filename_bytes)
        f.write(payload)

# valid1.czip
create_czip('/home/user/corpora/clean/valid1.czip', b'CZIP', 500, 'test.txt', b'A'*500)
# valid2.czip
create_czip('/home/user/corpora/clean/valid2.czip', b'CZIP', 2048, 'data.json', b'B'*2048)
# bomb.czip
create_czip('/home/user/corpora/evil/bomb.czip', b'CZIP', 99999999, 'bomb.txt', b'C'*100)
# traversal.czip
create_czip('/home/user/corpora/evil/traversal.czip', b'CZIP', 100, '../../etc/pass', b'D'*100)
# badmagic.czip
create_czip('/home/user/corpora/evil/badmagic.czip', b'BZIP', 100, 'a.txt', b'E'*100)
EOF

    python3 /tmp/generate_corpora.py
    rm /tmp/generate_corpora.py

    chmod -R 777 /home/user
