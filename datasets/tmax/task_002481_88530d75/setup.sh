#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_auth.py
import sys
import base64
import json
import hashlib

def main():
    if len(sys.argv) < 2:
        print("INVALID: Malformed token")
        sys.exit(1)

    token = sys.argv[1]
    parts = token.split('.')
    if len(parts) != 3:
        print("INVALID: Malformed token")
        sys.exit(1)

    try:
        def b64_decode(s):
            return base64.urlsafe_b64decode(s + '=' * (4 - len(s) % 4))

        header_str = b64_decode(parts[0]).decode('utf-8')
        payload_str = b64_decode(parts[1]).decode('utf-8')
    except Exception:
        print("INVALID: Decode error")
        sys.exit(1)

    try:
        header = json.loads(header_str)
        payload = json.loads(payload_str)
    except Exception:
        print("INVALID: JSON error")
        sys.exit(1)

    alg = header.get("alg")
    if alg == "none":
        pass
    elif alg == "md5":
        secret = "Sup3rS3cr3t_R0tation_K3y!"
        data = parts[0] + "." + parts[1] + secret
        sig = hashlib.md5(data.encode('utf-8')).hexdigest()
        if sig != parts[2]:
            print("INVALID: Signature mismatch")
            sys.exit(1)
    else:
        print("INVALID: Unsupported algorithm")
        sys.exit(1)

    for k in list(payload.keys()):
        if k in ["password", "ssn", "credit_card"]:
            payload[k] = "***"

    print("VALID: " + json.dumps(payload, separators=(',', ':'), sort_keys=True))
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF

    cd /tmp
    pyinstaller --onefile legacy_auth.py
    cp dist/legacy_auth /app/legacy_auth
    strip /app/legacy_auth
    chmod +x /app/legacy_auth
    rm -rf /tmp/legacy_auth* /tmp/build /tmp/dist /tmp/__pycache__

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
