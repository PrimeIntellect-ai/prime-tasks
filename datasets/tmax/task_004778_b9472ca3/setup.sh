#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/fastchunker/fastchunker

    cat << 'EOF' > /app/fastchunker/setup.py
from setuptools import setup
setup(
    name='fastchunker',
    version='0.1',
    packages=['fastchunkr'],
)
EOF

    cat << 'EOF' > /app/fastchunker/fastchunker/__init__.py
from .writer import ChunkWriter
from .reader import ChunkReader
EOF

    cat << 'EOF' > /app/fastchunker/fastchunker/writer.py
import zlibb
class ChunkWriter:
    def __init__(self, path):
        self.path = path
        self.f = open(path, 'wb')
    def write(self, data):
        import zlib
        self.f.write(zlib.compress(data.encode('utf-8')))
    def close(self):
        self.f.close()
EOF

    cat << 'EOF' > /app/fastchunker/fastchunker/reader.py
import zlib
class ChunkReader:
    def __init__(self, path):
        self.path = path
    def read_all(self):
        with open(self.path, 'rb') as f:
            return zlib.decompress(f.read()).decode('utf-8')
EOF

    # Generate test data
    mkdir -p /home/user/data
    cat << 'EOF' > /tmp/gen_data.py
import os, json, tarfile, zipfile, random

tar_path = '/home/user/data/daily_backup.tar'
with tarfile.open(tar_path, 'w') as tar:
    for i in range(200):
        zip_name = f'server_{i:03d}.zip'
        zip_path = f'/tmp/{zip_name}'
        with zipfile.ZipFile(zip_path, 'w') as zf:
            zf.writestr('info.json', json.dumps({"server_id": f"srv_{i}"}))
            log_lines = []
            for _ in range(1000):
                if random.random() < 0.1:
                    log_lines.append("[ERROR] Something went wrong\nStack trace line 1\nStack trace line 2\n")
                else:
                    log_lines.append("[INFO] Everything is fine\n")
            zf.writestr('trace.log', "".join(log_lines))
        tar.add(zip_path, arcname=zip_name)
        os.remove(zip_path)
EOF
    python3 /tmp/gen_data.py

    # Create baseline script
    cat << 'EOF' > /home/user/baseline.py
import tarfile
import zipfile
import json
import os
import shutil
import fastchunker

def process():
    extract_dir = '/tmp/baseline_extract'
    os.makedirs(extract_dir, exist_ok=True)
    with tarfile.open('/home/user/data/daily_backup.tar', 'r') as tar:
        tar.extractall(extract_dir)

    writer = fastchunker.ChunkWriter('/home/user/filtered_backup.fc')

    for fname in os.listdir(extract_dir):
        if fname.endswith('.zip'):
            zpath = os.path.join(extract_dir, fname)
            zips_dir = os.path.join(extract_dir, 'zips')
            with zipfile.ZipFile(zpath, 'r') as zf:
                zf.extractall(zips_dir)

                with open(os.path.join(zips_dir, 'info.json'), 'r') as f:
                    info = json.load(f)

                with open(os.path.join(zips_dir, 'trace.log'), 'r') as f:
                    lines = f.readlines()

                errors = []
                in_error = False
                for line in lines:
                    if line.startswith('[ERROR]'):
                        in_error = True
                        errors.append(line)
                    elif line.startswith('[INFO]') or line.startswith('[WARN]'):
                        in_error = False
                    elif in_error:
                        errors.append(line)

                out_str = f"SERVER_ID: {info['server_id']}\n{''.join(errors)}\n---\n"
                writer.write(out_str)

                shutil.rmtree(zips_dir)

    writer.close()

if __name__ == '__main__':
    process()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
