#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/config /app/data/raw /app/test_corpus/evil /app/test_corpus/clean

    cat << 'EOF' > /app/config/sanitizer_config.json
{"allowed_encodings": ["utf-8", "windows-1252", "shift_jis"], "target_encoding": "utf-8"}
EOF

    cat << 'EOF' > /app/server.py
import os
from flask import Flask, abort
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)
DOC_DIR = os.environ.get('DOC_DIR', '/home/user/processed_docs')

@app.route('/docs/<path:filename>')
def serve_doc(filename):
    try:
        cached = r.get(filename)
        if cached:
            return cached.decode('utf-8')
    except:
        pass

    filepath = os.path.join(DOC_DIR, filename)
    if not os.path.isfile(filepath):
        abort(404)

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    try:
        r.set(filename, content)
    except:
        pass
    return content

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    echo "Sample clean file" > /app/data/raw/sample.txt
    printf "Sample evil \x00 file" > /app/data/raw/evil.txt

    echo "Clean test file" > /app/test_corpus/clean/test_clean.txt
    printf "Evil test \x00 file" > /app/test_corpus/evil/test_evil.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
