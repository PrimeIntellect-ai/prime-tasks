#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
import hmac
import hashlib
import re

SECRET_KEY = b"sup3r_s3cr3t_k3y"

def verify_redirect(url, signature):
    # Verify the HMAC MD5 signature of the URL
    expected_sig = hmac.new(SECRET_KEY, url.encode('utf-8'), hashlib.md5).hexdigest()
    if not hmac.compare_digest(expected_sig, signature):
        return False

    # Simple WAF rule to prevent arbitrary external redirects
    if re.search(r'^https?://', url) and not url.startswith('https://trusted.com/'):
        return False

    return True
EOF

    chmod -R 777 /home/user
