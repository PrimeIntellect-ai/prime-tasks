#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/target_dir
    mkdir -p /home/user/protected

    echo -n "super_secret_audit_key_123" > /home/user/secret.key

    cat << 'EOF' > /home/user/upload_handler.py
import sys, hmac, hashlib, base64, urllib.parse, os

def verify_token(token):
    try:
        with open('/home/user/secret.key', 'rb') as f:
            key = f.read().strip()
        data, sig = token.split('.')
        expected_sig = hmac.new(key, data.encode(), hashlib.sha256).hexdigest()
        return hmac.compare_digest(sig, expected_sig) and data == "user=auditor"
    except Exception:
        return False

if len(sys.argv) != 4:
    print("Usage: python upload_handler.py <token> <filename> <b64_content>")
    sys.exit(1)

token, filename, b64_content = sys.argv[1:4]
if not verify_token(token):
    print("Invalid token")
    sys.exit(1)

# Naive check
if '../' in filename:
    print("Path traversal detected!")
    sys.exit(1)

# Decode after check (Vulnerability)
decoded_filename = urllib.parse.unquote(filename)
dest_path = os.path.abspath(os.path.join('/home/user/target_dir', decoded_filename))

# Prevent writing outside of /home/user entirely just as a safety net, 
# but allow writing to /home/user/protected to simulate successful exploit.
if not dest_path.startswith('/home/user/'):
    print("Out of bounds")
    sys.exit(1)

try:
    with open(dest_path, 'wb') as f:
        f.write(base64.b64decode(b64_content))
    print("File uploaded successfully")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
