#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /app/auth-redirect-v1.0.0
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/auth-redirect-v1.0.0/auth.py
from urllib.parse import urlparse

def extract_host(url):
    parsed = urlparse(url)
    host = parsed.netloc
    if ':' in host:
        parts = host.split(':')
        # BUG: returns port instead of host
        return parts[1]
    return host
EOF

    cat << 'EOF' > /app/auth-redirect-v1.0.0/test_auth.py
from auth import extract_host

def test_extract_host_no_port():
    assert extract_host("https://example.com/path") == "example.com"

def test_extract_host_with_port():
    assert extract_host("https://example.com:8080/path") == "example.com"
EOF

    cat << 'EOF' > /app/auth-redirect-v1.0.0/Makefile
test:
	pytest test_auth.py
EOF

    cat << 'EOF' > /opt/oracle/validate_redirect_oracle.py
#!/usr/bin/env python3
import sys
import urllib.parse
import re

def validate(allowed_domain, url):
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return "INVALID"

    path_lower = parsed.path.lower()
    if '../' in path_lower or '%2e%2e/' in path_lower:
        return "INVALID"

    if url.startswith('//'):
        return "INVALID"

    if url.startswith('/'):
        return f"SAFE: {url}"

    if parsed.scheme != 'https':
        return "INVALID"

    host = parsed.hostname
    if not host:
        return "INVALID"

    if host == allowed_domain or host.endswith('.' + allowed_domain):
        return f"SAFE: {url}"

    return "INVALID"

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("INVALID")
        sys.exit(1)

    res = validate(sys.argv[1], sys.argv[2])
    print(res)
EOF
    chmod +x /opt/oracle/validate_redirect_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
