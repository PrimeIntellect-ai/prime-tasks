#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/legacy-doc-parser-1.2.0/legacy_doc_parser

    # Create the broken reader.py
    cat << 'EOF' > /app/legacy-doc-parser-1.2.0/legacy_doc_parser/reader.py
import struct
import json

def parse_archive(filepath):
    with open(filepath, 'rb') as f:
        while True:
            length_bytes = f.read(4)
            if not length_bytes:
                break
            length = struct.unpack('>I', length_bytes)[0]
            payload = f.read(length)
            yield json.loads(payload.decode('utf-8'))
EOF

    # Create __init__.py
    touch /app/legacy-doc-parser-1.2.0/legacy_doc_parser/__init__.py

    # Create __main__.py
    cat << 'EOF' > /app/legacy-doc-parser-1.2.0/legacy_doc_parser/__main__.py
import sys
import json
from .reader import parse_archive

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: python -m legacy_doc_parser <file>")
    for record in parse_archive(sys.argv[1]):
        print(json.dumps(record))
EOF

    # Generate the legacy_docs.dat file
    cat << 'EOF' > /tmp/generate_docs.py
import struct, json
records = [
    {"doc_id": "D001", "category": "API", "title": "Auth V1", "content": "x"*500},
    {"doc_id": "D002", "category": "Guide", "title": "Getting Started", "content": "y"*800},
    {"doc_id": "D003", "category": "API", "title": "Billing", "content": "z"*600},
    {"doc_id": "D004", "category": "FAQ", "title": "Troubleshooting", "content": "w"*400},
    {"doc_id": "D005", "category": "Guide", "title": "Advanced Usage", "content": "v"*700}
]
with open('/home/user/legacy_docs.dat', 'wb') as f:
    for r in records:
        payload = json.dumps(r).encode('utf-8')
        f.write(struct.pack('<I', len(payload)))
        f.write(payload)
EOF
    python3 /tmp/generate_docs.py
    rm /tmp/generate_docs.py

    chmod -R 777 /home/user
