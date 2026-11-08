#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/loc_masker.py
import sys
import json
import re
import unicodedata

def process():
    email_regex = re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            if 'editor_ip' in data:
                parts = data['editor_ip'].split('.')
                if len(parts) == 4:
                    parts[3] = '0'
                    data['editor_ip'] = '.'.join(parts)
            for key in ['original', 'translated']:
                if key in data and isinstance(data[key], str):
                    val = unicodedata.normalize('NFKC', data[key])
                    val = email_regex.sub('[REDACTED]', val)
                    data[key] = val
            print(json.dumps(data, sort_keys=True, separators=(',', ':')))
        except Exception:
            pass

if __name__ == '__main__':
    process()
EOF

    pyinstaller --onefile /tmp/loc_masker.py --distpath /app -n loc_masker
    # Strip the pyinstaller bootloader
    strip /app/loc_masker || true
    chmod +x /app/loc_masker
    rm -rf /tmp/loc_masker.py build loc_masker.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
