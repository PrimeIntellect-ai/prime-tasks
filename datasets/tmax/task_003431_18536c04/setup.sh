#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis flask

    mkdir -p /home/user/archiver/corpus/clean
    mkdir -p /home/user/archiver/corpus/evil

    cat << 'EOF' > /home/user/archiver/redis.conf
port 0
unixsocket /home/user/archiver/redis.sock
unixsocketperm 777
daemonize yes
EOF

    cat << 'EOF' > /home/user/archiver/api.py
from flask import Flask, request
import redis
import uuid
import os

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379)

@app.route('/upload', methods=['POST'])
def upload():
    file_data = request.get_data()
    filename = str(uuid.uuid4()) + ".bin"
    filepath = os.path.join("/home/user/archiver", filename)
    with open(filepath, "wb") as f:
        f.write(file_data)
    r.lpush("backup_queue", filepath)
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/archiver/worker.py
import redis
import time
import os

r = redis.Redis(host='localhost', port=6379)

def main():
    while True:
        item = r.brpop("backup_queue", timeout=1)
        if item:
            filepath = item[1].decode('utf-8')
            if os.path.exists(filepath):
                with open(filepath, "rb") as f:
                    data = f.read()
                with open("/home/user/archiver/master_archive.bin", "ab") as f:
                    f.write(data)
        time.sleep(0.1)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/archiver/sanitizer.py
def sanitize_chunk(filepath):
    # TODO: Implement sanitization logic
    return True
EOF

    cat << 'EOF' > /tmp/generate_corpus.py
import os
import json
import struct
import hashlib

def make_chunk(magic=b"BKP1", header_len=None, header_dict=None, payload=b"", malformed_json=False):
    if header_dict is None:
        header_dict = {"timestamp": 1690000000, "source": "db_server", "checksum": hashlib.sha256(payload).hexdigest()}

    if malformed_json:
        header_bytes = b'{"timestamp": 1690000000, "source": "db_server"' # missing closing brace
    else:
        header_bytes = json.dumps(header_dict).encode('utf-8')

    if header_len is None:
        header_len = len(header_bytes)

    return magic + struct.pack("<I", header_len) + header_bytes + payload

clean_dir = "/home/user/archiver/corpus/clean"
evil_dir = "/home/user/archiver/corpus/evil"

# Generate 10 clean files
for i in range(10):
    payload = f"clean_payload_{i}".encode('utf-8')
    with open(os.path.join(clean_dir, f"clean_{i}.bin"), "wb") as f:
        f.write(make_chunk(payload=payload))

# Generate 10 evil files
# 1. Wrong magic
with open(os.path.join(evil_dir, "evil_0.bin"), "wb") as f:
    f.write(make_chunk(magic=b"BKP2", payload=b"evil"))
# 2. Header length > 1024
with open(os.path.join(evil_dir, "evil_1.bin"), "wb") as f:
    f.write(make_chunk(header_len=1025, payload=b"evil"))
# 3. Malformed JSON
with open(os.path.join(evil_dir, "evil_2.bin"), "wb") as f:
    f.write(make_chunk(malformed_json=True, payload=b"evil"))
# 4. source="test"
with open(os.path.join(evil_dir, "evil_3.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "source": "test", "checksum": hashlib.sha256(b"evil").hexdigest()}
    f.write(make_chunk(header_dict=hd, payload=b"evil"))
# 5. source="unknown"
with open(os.path.join(evil_dir, "evil_4.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "source": "unknown", "checksum": hashlib.sha256(b"evil").hexdigest()}
    f.write(make_chunk(header_dict=hd, payload=b"evil"))
# 6. Mismatched checksum
with open(os.path.join(evil_dir, "evil_5.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "source": "db_server", "checksum": "wrong"}
    f.write(make_chunk(header_dict=hd, payload=b"evil"))
# 7. Missing checksum
with open(os.path.join(evil_dir, "evil_6.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "source": "db_server"}
    f.write(make_chunk(header_dict=hd, payload=b"evil"))
# 8. Missing source
with open(os.path.join(evil_dir, "evil_7.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "checksum": hashlib.sha256(b"evil").hexdigest()}
    f.write(make_chunk(header_dict=hd, payload=b"evil"))
# 9. Header length mismatch (too short)
with open(os.path.join(evil_dir, "evil_8.bin"), "wb") as f:
    f.write(make_chunk(header_len=5, payload=b"evil"))
# 10. Empty payload but checksum expects something else
with open(os.path.join(evil_dir, "evil_9.bin"), "wb") as f:
    hd = {"timestamp": 1690000000, "source": "db_server", "checksum": hashlib.sha256(b"something").hexdigest()}
    f.write(make_chunk(header_dict=hd, payload=b""))
EOF
    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
