#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest SpeechRecognition

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hello team, just a reminder that for the new login flow, the shared salt is winter storm. Don't forget to update your configs."

    mkdir -p /verify
    cat << 'EOF' > /verify/oracle.py
import sys
import json
import hashlib
from urllib.parse import urlparse, parse_qs

def verify():
    try:
        data = json.loads(sys.stdin.read())
        host = data.get('host', '')
        path = data.get('path', '')
        cookie = data.get('cookie', '')

        # Rule 1
        salt = "winter storm"
        expected_hash = hashlib.sha256(f"{host}{path}{salt}".encode()).hexdigest()

        if not cookie.startswith("auth_sig=") or cookie.split("=")[1] != expected_hash:
            print("DENY: INVALID_SIGNATURE")
            return

        # Parse query string
        parsed_path = urlparse(path)
        qs = parse_qs(parsed_path.query)
        next_val = qs.get('next', [''])[0]

        if next_val:
            # Rule 2
            next_lower = next_val.lower()
            if 'javascript:' in next_lower or 'data:' in next_lower or '../' in next_lower:
                print("DENY: MALICIOUS_PAYLOAD")
                return

            # Rule 3
            if next_val.startswith('//'):
                print("DENY: OPEN_REDIRECT")
                return

            parsed_next = urlparse(next_val)
            if parsed_next.scheme in ['http', 'https']:
                if parsed_next.hostname != host:
                    print("DENY: OPEN_REDIRECT")
                    return

        # Rule 4
        print("ALLOW")
    except Exception:
        print("DENY: INVALID_SIGNATURE") # Fallback for parsing errors to match fuzz baseline

if __name__ == '__main__':
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
