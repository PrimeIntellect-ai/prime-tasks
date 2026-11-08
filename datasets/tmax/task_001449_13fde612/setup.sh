#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest pyinstaller

cat << 'EOF' > /tmp/oracle.py
import sys
import re
import hashlib

def process(text):
    text = text.rstrip('\n')
    text = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', 'XXX-XX-XXXX', text)
    if '../' in text or '..\\' in text:
        text = '[CWE-22 DETECTED] ' + text
    h = hashlib.sha256(text.encode('utf-8')).hexdigest()
    return f"{text}\t{h}\n"

if __name__ == '__main__':
    input_text = sys.stdin.read()
    sys.stdout.write(process(input_text))
EOF

pyinstaller --onefile /tmp/oracle.py
mkdir -p /app
mv dist/oracle /app/legacy_audit_processor
chmod +x /app/legacy_audit_processor
rm -rf /tmp/oracle.py build dist oracle.spec

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
