#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor/archivetool/archivetool
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create vendored library setup.py
    cat << 'EOF' > /app/vendor/archivetool/setup.py
from setuptools import setup, find_packages
setup(name='archivetool', version='1.0.0', packages=find_packages())
EOF

    # Create vendored library __init__.py
    touch /app/vendor/archivetool/archivetool/__init__.py

    # Create vendored library core.py with deliberate bug
    cat << 'EOF' > /app/vendor/archivetool/archivetool/core.py
import os
import zipfile

CONFIG_DIR = os.environ['ARCHIVETOOL_CONFIG']

def verify_archive(filepath):
    if not zipfile.is_zipfile(filepath):
        raise ValueError("Not an archive")
    try:
        with zipfile.ZipFile(filepath) as z:
            return z.testzip() is None
    except Exception:
        return False
EOF

    # Generate corpus files
    python3 -c "
import zipfile
import os

# Clean corpus
with open('/app/corpora/clean/clean_text_utf8.txt', 'w', encoding='utf-8') as f:
    f.write('This is a clean file.')

with open('/app/corpora/clean/clean_text_utf16.txt', 'w', encoding='utf-16') as f:
    f.write('This is a clean file in utf16.')

with zipfile.ZipFile('/app/corpora/clean/clean_archive.zip', 'w') as z:
    z.writestr('test.txt', 'clean archive')

# Evil corpus
with open('/app/corpora/evil/evil_text_utf8.txt', 'w', encoding='utf-8') as f:
    f.write('This is [MALICIOUS_MACRO] inside.')

with open('/app/corpora/evil/evil_text_iso8859.txt', 'w', encoding='iso-8859-1') as f:
    f.write('This is [MALICIOUS_MACRO] with \x80 high bytes.')

with zipfile.ZipFile('/app/corpora/evil/corrupted_archive.zip', 'w') as z:
    z.writestr('test.txt', 'evil archive')

# Corrupt the zip file
with open('/app/corpora/evil/corrupted_archive.zip', 'r+b') as f:
    f.seek(10)
    f.write(b'\x00\x00\x00\x00')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
