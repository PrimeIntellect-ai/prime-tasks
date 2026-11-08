#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo rustc
    pip3 install pytest flask requests

    mkdir -p /app
    mkdir -p /home/user/incoming
    mkdir -p /home/user/projects
    mkdir -p /home/user/organizer

    cat << 'EOF' > /app/upload_app.py
from flask import Flask, request
import os

app = Flask(__name__)
INCOMING_DIR = '/home/user/incoming'

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if file:
        os.makedirs(INCOMING_DIR, exist_ok=True)
        file.save(os.path.join(INCOMING_DIR, file.filename))
        return "OK"
    return "No file", 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/analytics_app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

GOLDEN = {
    "test1.tar": {"extracted_bin": 1, "extracted_src": 2, "extracted_db": 0, "ignored_malicious": 1},
    "test2.tar": {"extracted_bin": 0, "extracted_src": 5, "extracted_db": 1, "ignored_malicious": 2},
    "test3.tar": {"extracted_bin": 2, "extracted_src": 1, "extracted_db": 1, "ignored_malicious": 1},
    "test4.tar": {"extracted_bin": 0, "extracted_src": 0, "extracted_db": 2, "ignored_malicious": 3},
    "test5.tar": {"extracted_bin": 1, "extracted_src": 1, "extracted_db": 1, "ignored_malicious": 0},
}

results = {}

@app.route('/report', methods=['POST'])
def report():
    data = request.json
    archive = data.get('archive')
    results[archive] = data
    return "OK"

@app.route('/score', methods=['GET'])
def score():
    correct = 0
    for archive, expected in GOLDEN.items():
        if archive in results:
            res = results[archive]
            if (res.get('extracted_bin') == expected['extracted_bin'] and
                res.get('extracted_src') == expected['extracted_src'] and
                res.get('extracted_db') == expected['extracted_db'] and
                res.get('ignored_malicious') == expected['ignored_malicious']):
                correct += 1
    score = correct / len(GOLDEN) if len(GOLDEN) > 0 else 0
    return jsonify({"score": score})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

    cat << 'EOF' > /app/generate_and_upload.py
import tarfile
import io
import requests
import os

def make_file(path, data):
    info = tarfile.TarInfo(name=path)
    info.size = len(data)
    return info, io.BytesIO(data)

def create_and_upload(name, files):
    path = os.path.join('/app', name)
    with tarfile.open(path, 'w') as tar:
        for p, data in files:
            info, fileobj = make_file(p, data)
            tar.addfile(tarinfo=info, fileobj=fileobj)

    with open(path, 'rb') as f:
        requests.post('http://127.0.0.1:5000/upload', files={'file': f})

ELF = b'\x7fELF' + b'\x00'*10
SRC = b'valid utf8 text'
DB = b'SQLite format 3\x00' + b'\x00'*10

archives = {
    "test1.tar": [
        ("bin1", ELF),
        ("src1.txt", SRC),
        ("src2.txt", SRC),
        ("../../../etc/passwd", SRC)
    ],
    "test2.tar": [
        ("src1", SRC), ("src2", SRC), ("src3", SRC), ("src4", SRC), ("src5", SRC),
        ("db1.db", DB),
        ("../../var/log/syslog", SRC),
        ("project/../../../root/.bashrc", SRC)
    ],
    "test3.tar": [
        ("bin1", ELF), ("bin2", ELF),
        ("src1", SRC),
        ("db1", DB),
        ("/etc/shadow", SRC)
    ],
    "test4.tar": [
        ("db1", DB), ("db2", DB),
        ("../a", SRC), ("../../b", SRC), ("/c", SRC)
    ],
    "test5.tar": [
        ("bin1", ELF),
        ("src1", SRC),
        ("db1", DB)
    ]
}

for name, files in archives.items():
    create_and_upload(name, files)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nohup python3 /app/upload_app.py > /app/upload.log 2>&1 &
nohup python3 /app/analytics_app.py > /app/analytics.log 2>&1 &
sleep 2
EOF

    cat << 'EOF' > /app/trigger_uploads.sh
#!/bin/bash
python3 /app/generate_and_upload.py
EOF

    cat << 'EOF' > /app/verify.py
import requests
import sys

try:
    res = requests.get('http://127.0.0.1:5001/score')
    score = res.json().get('score', 0)
    if score >= 1.0:
        print("Success")
        sys.exit(0)
    else:
        print(f"Score: {score}")
        sys.exit(1)
except Exception as e:
    print(e)
    sys.exit(1)
EOF

    chmod +x /app/start_services.sh /app/trigger_uploads.sh
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user /app
