#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zlib1g-dev sudo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import struct
import zlib
import os

os.makedirs('/home/user', exist_ok=True)

# 1. Create extraction.conf
conf_content = """Extract-Prefix: /home/user/extracted_docs
Target-Categories: API,Tutorial
Other-Setting: IgnoreThis
"""
with open('/home/user/extraction.conf', 'w') as f:
    f.write(conf_content)

# 2. Create archive.pak
def make_record(rec_type, category, doc_id, payload):
    cat_bytes = category.encode('ascii')
    header = struct.pack('<cB', rec_type.encode('ascii'), len(cat_bytes))
    header += cat_bytes
    header += struct.pack('<II', doc_id, len(payload))
    return header + payload

logs_payload_1 = """BEGIN_LOG
DocID: 101
Version: 1
Status: RELEASED
END_LOG
BEGIN_LOG
DocID: 101
Version: 2
Status: DRAFT
END_LOG
""".encode('ascii')

logs_payload_2 = """BEGIN_LOG
DocID: 202
Version: 1
Status: RELEASED
END_LOG
BEGIN_LOG
DocID: 202
Version: 3
Status: RELEASED
END_LOG
""".encode('ascii')

logs_payload_3 = """BEGIN_LOG
DocID: 303
Version: 1
Status: DRAFT
END_LOG
""".encode('ascii')

doc_101 = zlib.compress(b"This is the API documentation.")
doc_202 = zlib.compress(b"This is the Tutorial documentation.")
doc_303 = zlib.compress(b"This is Architecture, should be ignored by category.")
doc_404 = zlib.compress(b"This is API but never released.")

with open('/home/user/archive.pak', 'wb') as f:
    f.write(b'ARCv1')
    f.write(make_record('L', 'API', 101, logs_payload_1))
    f.write(make_record('C', 'API', 101, doc_101))

    f.write(make_record('C', 'Tutorial', 202, doc_202))
    f.write(make_record('L', 'Tutorial', 202, logs_payload_2))

    f.write(make_record('C', 'Architecture', 303, doc_303))
    f.write(make_record('L', 'Architecture', 303, logs_payload_3))

    f.write(make_record('C', 'API', 404, doc_404))
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
