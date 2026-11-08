#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl john
    pip3 install pytest

    mkdir -p /home/user/audit/keys

    cat << 'EOF' > /home/user/audit/keys/wordlist.txt
qwerty
password
admin
letmein
secret123
sunshine
dragon
EOF

    openssl genrsa -aes256 -passout pass:secret123 -out /home/user/audit/keys/client_key.pem.enc 2048

    cat << 'EOF' > /home/user/audit/auth_module.py
import json
import base64

def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)

def verify_token(jwt_token, public_key):
    try:
        parts = jwt_token.split('.')
        if len(parts) != 3:
            return False

        header_b64, payload_b64, signature_b64 = parts

        header = json.loads(base64url_decode(header_b64).decode('utf-8'))
        payload = json.loads(base64url_decode(payload_b64).decode('utf-8'))

        # VULNERABILITY: accepts 'none' algorithm
        if header.get('alg', '').lower() == 'none':
            # Skip signature verification
            pass
        else:
            # Pseudo-code for normal signature verification
            if not verify_signature(header_b64 + "." + payload_b64, signature_b64, public_key):
                return False

        if payload.get('user') == 'admin':
            return True

        return False
    except Exception as e:
        return False

def verify_signature(data, signature, public_key):
    # Stub for actual RSA verification
    return False
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/audit
    chmod -R 777 /home/user
