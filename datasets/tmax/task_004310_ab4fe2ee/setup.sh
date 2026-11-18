#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app /verify

    # Generate the audio file
    espeak -w /app/voicemail.wav "The secret salt is xenolith."

    # Create the oracle script
    cat << 'EOF' > /verify/oracle_filter.py
import sys
import json
import unicodedata
import hashlib

def main():
    salt = "xenolith"
    seen_hashes = set()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        if 'user_id' not in data or 'message' not in data:
            continue

        norm_msg = unicodedata.normalize('NFKC', data['message'])

        to_hash = (norm_msg + salt).encode('utf-8')
        h = hashlib.sha256(to_hash).hexdigest()

        if h in seen_hashes:
            continue
        seen_hashes.add(h)

        last_4 = h[-4:]
        val = int(last_4, 16)

        if val % 3 == 0:
            data['message'] = norm_msg
            data['hash'] = h
            print(json.dumps(data, separators=(',', ':')))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
