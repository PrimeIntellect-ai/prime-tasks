#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis pyelftools

    mkdir -p /home/user/artifact_manager/logs
    mkdir -p /home/user/artifact_manager/uploads
    mkdir -p /home/user/artifact_manager/curated
    mkdir -p /app

    cat << 'EOF' > /home/user/artifact_manager/config.ini
[Settings]
queue_type = memory
redis_url = redis://127.0.0.1:6379/0
EOF

    cat << 'EOF' > /home/user/artifact_manager/app.py
import os
import configparser
import redis
from flask import Flask, request
import logging

app = Flask(__name__)
config = configparser.ConfigParser()
config.read('/home/user/artifact_manager/config.ini')

os.makedirs('/home/user/artifact_manager/uploads', exist_ok=True)
os.makedirs('/home/user/artifact_manager/logs', exist_ok=True)

logging.basicConfig(filename='/home/user/artifact_manager/logs/upload.log', level=logging.INFO)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return 'No file part', 400
    file = request.files['file']
    if file.filename == '':
        return 'No selected file', 400
    if file:
        filepath = os.path.join('/home/user/artifact_manager/uploads', file.filename)
        file.save(filepath)
        logging.info(f"Uploaded: {filepath}")

        queue_type = config.get('Settings', 'queue_type', fallback='memory')
        if queue_type == 'redis':
            redis_url = config.get('Settings', 'redis_url')
            r = redis.from_url(redis_url)
            r.lpush('upload_queue', filepath)

        return 'File uploaded successfully', 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/artifact_manager/worker.py
import os
import time
import redis
import subprocess
import configparser

config = configparser.ConfigParser()
config.read('/home/user/artifact_manager/config.ini')

def process_queue():
    queue_type = config.get('Settings', 'queue_type', fallback='memory')
    if queue_type != 'redis':
        return

    redis_url = config.get('Settings', 'redis_url')
    r = redis.from_url(redis_url)

    while True:
        item = r.brpop('upload_queue', timeout=5)
        if item:
            filepath = item[1].decode('utf-8')
            parser_path = '/home/user/artifact_manager/elf_parser.py'
            if os.path.exists(parser_path):
                result = subprocess.run(['python3', parser_path, filepath], capture_output=True, text=True)
                output = result.stdout.strip()
                if output:
                    # TODO: Implement symlink logic here
                    pass
        time.sleep(1)

if __name__ == '__main__':
    process_queue()
EOF

    cat << 'EOF' > /home/user/artifact_manager/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/artifact_manager/app.py &
python3 /home/user/artifact_manager/worker.py &
EOF
    chmod +x /home/user/artifact_manager/start_services.sh

    cat << 'EOF' > /app/oracle_parser.py
import sys
from elftools.elf.elffile import ELFFile

def parse_elf(filepath):
    with open(filepath, 'rb') as f:
        elffile = ELFFile(f)
        machine = elffile.header['e_machine']
        entry = hex(elffile.header['e_entry'])
        text_section = elffile.get_section_by_name('.text')
        size = text_section['sh_size'] if text_section else 0
        print(f"{machine}|{entry}|{size}")

if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_elf(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
