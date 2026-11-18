#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc
    pip3 install pytest flask redis

    mkdir -p /app/service
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /app/service/app.py
from flask import Flask, request, jsonify
import redis
import os
import subprocess
import zlib

app = Flask(__name__)
# Bug: wrong port
r = redis.Redis(host='127.0.0.1', port=6370, db=0)

@app.route('/build', methods=['POST'])
def build():
    data = request.get_json()
    source = data.get("source_code", "")
    # Bug: missing os.makedirs('/tmp/builds', exist_ok=True)
    source_path = "/tmp/builds/temp.c"
    so_path = "/tmp/builds/temp.so"

    with open(source_path, "w") as f:
        f.write(source)

    subprocess.run(["gcc", "-shared", "-fPIC", "-o", so_path, source_path], check=True)

    with open(so_path, "rb") as f:
        crc = zlib.crc32(f.read())

    r.set("latest_build", crc)
    return jsonify({"checksum": str(crc)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Create 10 clean JSON files
    for i in $(seq 1 10); do
        cat << EOF > /app/corpora/clean/clean_$i.json
{"source_code": "int add(int a, int b) { return a + b + $i; }"}
EOF
    done

    # Create 10 evil JSON files
    for i in $(seq 1 10); do
        cat << EOF > /app/corpora/evil/evil_$i.json
{"source_code": "#include <stdlib.h>\nvoid run() { system(\"ls -l $i\"); }"}
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
