#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest setuptools

    # Create vendored package
    mkdir -p /app/vendored/text_sanitizer-1.0.0/text_sanitizer

    cat << 'EOF' > /app/vendored/text_sanitizer-1.0.0/setup.py
from setuptools import setup

setup(
    name='text_sanitizer',
    version='1.0.0',
    packages=['wrong_name'],
)
EOF

    touch /app/vendored/text_sanitizer-1.0.0/text_sanitizer/__init__.py

    cat << 'EOF' > /app/vendored/text_sanitizer-1.0.0/text_sanitizer/core.py
import re

def sanitize_text(text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text
EOF

    # Create archives
    mkdir -p /home/user
    mkdir -p /tmp/archives
    cd /tmp/archives

    echo '{"content": "Welcome to MacroHard."}' > doc_1.json
    zip valid1.zip doc_1.json

    echo '<root><Body>MacroHard is great!</Body></root>' > doc_2.xml
    tar -czf valid2.tar.gz doc_2.xml

    head -c 100 /dev/urandom > corrupt3.zip

    tar -czf /home/user/raw_docs.tar.gz valid1.zip valid2.tar.gz corrupt3.zip

    cd /
    rm -rf /tmp/archives

    # Create golden file
    cat << 'EOF' > /tmp/golden_documentation.md
Welcome to NovaTech.

NovaTech is great!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
