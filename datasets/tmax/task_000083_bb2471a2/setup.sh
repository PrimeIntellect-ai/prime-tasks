#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server cargo zip unzip tar curl gawk coreutils
pip3 install pytest flask redis

mkdir -p /app/corpus/clean /app/corpus/evil
mkdir -p /home/user/spool /home/user/processed

cat << 'EOF' > /app/flask_api.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/register_backup', methods=['POST'])
def register_backup():
    data = request.json
    print(f"Registered backup: {data}")
    return jsonify({"status": "success"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/flask_api.py &
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /tmp/setup_corpus.py
import os
import hashlib
import zipfile

def create_clean(base_dir, num):
    path = os.path.join(base_dir, f"dir{num}")
    os.makedirs(path)
    file_path = os.path.join(path, "data.txt")
    with open(file_path, "w") as f:
        f.write("hello")
    chk = hashlib.sha256(b"hello").hexdigest()
    with open(os.path.join(path, "backup.log"), "w") as f:
        f.write(f"BEGIN FILE: data.txt\nCHECKSUM: {chk}\nEND FILE\n")

def create_evil(base_dir, num, evil_type):
    path = os.path.join(base_dir, f"dir{num}")
    os.makedirs(path)

    file_path = os.path.join(path, "data.txt")
    with open(file_path, "w") as f:
        f.write("hello")
    chk = hashlib.sha256(b"hello").hexdigest()

    if evil_type == "zip_sh":
        with zipfile.ZipFile(os.path.join(path, "nested.zip"), "w") as z:
            z.writestr("script.sh", "echo bad")
        with open(os.path.join(path, "backup.log"), "w") as f:
            f.write(f"BEGIN FILE: data.txt\nCHECKSUM: {chk}\nEND FILE\n")
    elif evil_type == "mismatch":
        with open(os.path.join(path, "backup.log"), "w") as f:
            f.write(f"BEGIN FILE: data.txt\nCHECKSUM: 0000000000000000000000000000000000000000000000000000000000000000\nEND FILE\n")
    elif evil_type == "exec":
        os.chmod(file_path, 0o755)
        with open(os.path.join(path, "backup.log"), "w") as f:
            f.write(f"BEGIN FILE: data.txt\nCHECKSUM: {chk}\nEND FILE\n")
    elif evil_type == "elf":
        with open(os.path.join(path, "bad.elf"), "w") as f:
            f.write("bad")
        with open(os.path.join(path, "backup.log"), "w") as f:
            f.write(f"BEGIN FILE: data.txt\nCHECKSUM: {chk}\nEND FILE\n")
    elif evil_type == "missing":
        with open(os.path.join(path, "backup.log"), "w") as f:
            f.write(f"BEGIN FILE: data.txt\nCHECKSUM: {chk}\nEND FILE\n")
            f.write(f"BEGIN FILE: missing.txt\nCHECKSUM: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef\nEND FILE\n")

for i in range(1, 6):
    create_clean("/app/corpus/clean", i)

evil_types = ["zip_sh", "mismatch", "exec", "elf", "missing"]
for i in range(1, 6):
    create_evil("/app/corpus/evil", i, evil_types[i-1])
EOF

python3 /tmp/setup_corpus.py
rm /tmp/setup_corpus.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
