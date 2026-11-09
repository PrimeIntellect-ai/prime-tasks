#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest requests redis flask gunicorn aiohttp

    mkdir -p /home/user/docs_raw
    mkdir -p /home/user/docs_processed
    mkdir -p /app

    # Generate 10000 files
    python3 -c '
import os
import random

for i in range(10000):
    with open(f"/home/user/docs_raw/doc_{i:05d}.md", "w") as f:
        content = "Some random text.\n" * 10
        num_refs = random.randint(1, 5)
        for _ in range(num_refs):
            target = f"DOC_{random.randint(1000, 9999)}"
            content += f"<legacy-ref target=\"{target}\">\n"
        f.write(content)
'

    cat << 'EOF' > /app/api.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/report', methods=['POST'])
def report():
    data = request.json
    if data and 'filename' in data:
        r.set(data['filename'], data.get('replacements', 0))
    return "OK", 200
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn -w 4 -b 127.0.0.1:5000 --chdir /app api:app --daemon
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/processor.py
import os
import re
import requests

def process():
    raw_dir = '/home/user/docs_raw'
    out_dir = '/home/user/docs_processed'
    for filename in os.listdir(raw_dir):
        if not filename.endswith('.md'): continue
        path = os.path.join(raw_dir, filename)
        with open(path, 'r') as f:
            content = f.read()

        matches = re.findall(r'<legacy-ref target="(.*?)">', content)
        replacements = len(matches)
        for m in matches:
            content = content.replace(f'<legacy-ref target="{m}">', f'[{m}](/docs/{m})')

        out_path = os.path.join(out_dir, filename)
        with open(out_path, 'w') as f:
            f.write(content)

        try:
            requests.post('http://127.0.0.1:5000/report', json={"filename": filename, "replacements": replacements})
        except:
            pass

if __name__ == "__main__":
    process()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
