#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import gzip
import io

# 1. Create files for the tar archive
os.makedirs("/tmp/doc_setup", exist_ok=True)
with open("/tmp/doc_setup/index.txt", "w", encoding="utf-16le") as f:
    f.write("Welcome to the documentation.\n")
with open("/tmp/doc_setup/main.css", "w", encoding="iso-8859-1") as f:
    f.write("body { background: white; }\n")

# 2. Create the tarball in memory
tar_stream = io.BytesIO()
with tarfile.open(fileobj=tar_stream, mode="w") as tar:
    tar.add("/tmp/doc_setup/index.txt", arcname="docs/index.txt")
    # Simulate malicious zip-slip path
    tar.add("/tmp/doc_setup/main.css", arcname="../styles/main.css")

# 3. Compress the tarball
gzip_stream = io.BytesIO()
with gzip.GzipFile(fileobj=gzip_stream, mode="w") as gz:
    gz.write(tar_stream.getvalue())
compressed_data = gzip_stream.getvalue()

# 4. Create multi-line log
log_data = """[INFO] Build started
[INFO] Loading resources...
[WARNING] Font missing
Falling back to default sans-serif font.
Please install the required fonts.
[INFO] Processing markdown
[ERROR] Broken link
[WARNING] Unused stylesheet
The main.css file is not linked.
[INFO] Build complete
"""
log_bytes = log_data.encode("iso-8859-1")

# 5. Build final binary file
header = b"DOCMGR_V1".ljust(128, b'\x00')

with open("/home/user/doc_bundle.bin", "wb") as f:
    f.write(header)
    f.write(compressed_data)
    f.write(log_bytes)
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/doc_setup /tmp/setup.py

    chmod -R 777 /home/user
